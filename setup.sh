#!/bin/bash

# Create necessary directories
mkdir -p prometheus grafana/provisioning/datasources grafana/provisioning/dashboards

# Create Dockerfile for Rails application
cat > Dockerfile << 'EOF'
FROM ruby:3.4.4

# Install dependencies
RUN apt-get update -qq && apt-get install -y nodejs postgresql-client

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile* ./
RUN bundle install

# Copy the rest of the application
COPY . .

# Start the Rails server
CMD ["rails", "server", "-b", "0.0.0.0"]
EOF

# Create Gemfile
cat > Gemfile << 'EOF'
source "https://rubygems.org"

# Prometheus Ruby Client [https://github.com/prometheus/client_ruby]
gem "prometheus-client"
# Use Redis for caching and session storage
gem "redis"
# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
EOF

# Create a basic Rails application
docker compose run --rm web rails new . --skip --database=postgresql --skip-bundle

# Start the services
docker compose up -d

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker compose exec db pg_isready -U postgres > /dev/null 2>&1; do
  sleep 2
done

# Create and migrate the database
docker compose exec web rails db:create db:migrate

# Create Hello World controller
cat > ./app/controllers/hello_controller.rb << 'HELLO_EOF'
class HelloController < ApplicationController
  def index
    render plain: "Hello World!"
  end
end
HELLO_EOF

# Update routes for Hello World application
cat > ./config/routes.rb << 'ROUTES_EOF'
Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Hello World routes
  root "hello#index"
  get "hello", to: "hello#index"

  # Defines the root path route ("/")
  # root "posts#index" 
end
ROUTES_EOF

# APM middleware configuration
# Create middleware folder
mkdir -p ./lib/prometheus/middleware

# Create Collector
cat > ./lib/prometheus/middleware/collector.rb << 'COLLECTOR_EOF'
# encoding: UTF-8

require 'benchmark'
require 'prometheus/client'

module Prometheus
  module Middleware
    # Collector is a Rack middleware that provides a sample implementation of a
    # HTTP tracer.
    #
    # By default metrics are registered on the global registry. Set the
    # `:registry` option to use a custom registry.
    #
    # By default metrics all have the prefix "http_server". Set
    # `:metrics_prefix` to something else if you like.
    #
    # The request counter metric is broken down by code, method and path.
    # The request duration metric is broken down by method and path.
    class Collector
      attr_reader :app, :registry

      def initialize(app, options = {})
        @app = app
        @registry = options[:registry] || Client.registry
        @metrics_prefix = options[:metrics_prefix] || 'http_server'

        init_request_metrics
        init_exception_metrics
      end

      def call(env) # :nodoc:
        trace(env) { @app.call(env) }
      end

      protected

      def init_request_metrics
        @requests = @registry.counter(
          :"#{@metrics_prefix}_requests_total",
          docstring:
            'The total number of HTTP requests handled by the Rack application.',
          labels: %i[code method path]
        )
        @durations = @registry.histogram(
          :"#{@metrics_prefix}_request_duration_seconds",
          docstring: 'The HTTP response duration of the Rack application.',
          labels: %i[method path]
        )
      end

      def init_exception_metrics
        @exceptions = @registry.counter(
          :"#{@metrics_prefix}_exceptions_total",
          docstring: 'The total number of exceptions raised by the Rack application.',
          labels: [:exception]
        )
      end

      def trace(env)
        response = nil
        duration = Benchmark.realtime { response = yield }
        record(env, response.first.to_s, duration)
        return response
      rescue => exception
        @exceptions.increment(labels: { exception: exception.class.name })
        raise
      end

      def record(env, code, duration)
        path = generate_path(env)

        counter_labels = {
          code:   code,
          method: env['REQUEST_METHOD'].downcase,
          path:   path,
        }

        duration_labels = {
          method: env['REQUEST_METHOD'].downcase,
          path:   path,
        }

        @requests.increment(labels: counter_labels)
        @durations.observe(duration, labels: duration_labels)
      rescue
        # TODO: log unexpected exception during request recording
        nil
      end

      def generate_path(env)
        full_path = [env['SCRIPT_NAME'], env['PATH_INFO']].join

        strip_ids_from_path(full_path)
      end

      def strip_ids_from_path(path)
        path
          .gsub(%r{/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?=/|$)}, '/:uuid\\1')
          .gsub(%r{/\d+(?=/|$)}, '/:id\\1')
      end
    end
  end
end
COLLECTOR_EOF

#Create Exporter
cat > ./lib/prometheus/middleware/exporter.rb << 'EXPORTER_EOF'
# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/formats/text'

module Prometheus
  module Middleware
    # Exporter is a Rack middleware that provides a sample implementation of a
    # Prometheus HTTP exposition endpoint.
    #
    # By default it will export the state of the global registry and expose it
    # under `/metrics`. Use the `:registry` and `:path` options to change the
    # defaults.
    class Exporter
      attr_reader :app, :registry, :path

      FORMATS  = [Client::Formats::Text].freeze
      FALLBACK = Client::Formats::Text

      def initialize(app, options = {})
        @app = app
        @registry = options[:registry] || Client.registry
        @path = options[:path] || '/metrics'
        @port = options[:port]
        @acceptable = build_dictionary(FORMATS, FALLBACK)
      end

      def call(env)
        if metrics_port?(env['SERVER_PORT']) && env['PATH_INFO'] == @path
          format = negotiate(env, @acceptable)
          format ? respond_with(format) : not_acceptable(FORMATS)
        else
          @app.call(env)
        end
      end

      private

      def negotiate(env, formats)
        parse(env.fetch('HTTP_ACCEPT', '*/*')).each do |content_type, _|
          return formats[content_type] if formats.key?(content_type)
        end

        nil
      end

      def parse(header)
        header.split(/\s*,\s*/).map do |type|
          attributes = type.split(/\s*;\s*/)
          quality = extract_quality(attributes)

          [attributes.join('; '), quality]
        end.sort_by(&:last).reverse
      end

      def extract_quality(attributes, default = 1.0)
        quality = default

        attributes.delete_if do |attr|
          quality = attr.split('q=').last.to_f if attr.start_with?('q=')
        end

        quality
      end

      def respond_with(format)
        [
          200,
          { 'content-type' => format::CONTENT_TYPE },
          [format.marshal(@registry)],
        ]
      end

      def not_acceptable(formats)
        types = formats.map { |format| format::MEDIA_TYPE }

        [
          406,
          { 'content-type' => 'text/plain' },
          ["Supported media types: #{types.join(', ')}"],
        ]
      end

      def build_dictionary(formats, fallback)
        formats.each_with_object('*/*' => fallback) do |format, memo|
          memo[format::CONTENT_TYPE] = format
          memo[format::MEDIA_TYPE] = format
        end
      end

      def metrics_port?(request_port)
        @port.nil? || @port.to_s == request_port
      end
    end
  end
end
EXPORTER_EOF

# Enable Prometheus middlware
cat  <<'CONFIG_EOF'>> config.ru

require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'

use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter
CONFIG_EOF

# Enable Redis cache for dev environment
# Path to your config file
DEV_CONFIG="./config/environments/development.rb"

# Replace or add config.cache_store line
if grep -q "config.cache_store" "$DEV_CONFIG"; then
  sed -i "s|.*config.cache_store.*|  config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }|" "$DEV_CONFIG"
else
  sed -i "/Rails.application.configure do/a \  config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }" "$DEV_CONFIG"
fi

# Replace or add config.action_controller.perform_caching line
if grep -q "config.action_controller.perform_caching" "$DEV_CONFIG"; then
  sed -i "s|.*config.action_controller.perform_caching.*|  config.action_controller.perform_caching = true|" "$DEV_CONFIG"
else
  sed -i "/Rails.application.configure do/a \  config.action_controller.perform_caching = true" "$DEV_CONFIG"
fi

# Restart the web service to apply changes
docker compose restart web

echo "Setup complete! The application is now running at:"
echo "Rails app: http://localhost:3000"
echo "Grafana: http://localhost:3001"
echo "Prometheus: http://localhost:9090"