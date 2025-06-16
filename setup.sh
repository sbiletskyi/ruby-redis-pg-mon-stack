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
sleep 30

# Create and migrate the database
docker compose exec web rails db:create db:migrate

# Create Hello World controller
docker compose exec web bash -c 'cat > app/controllers/hello_controller.rb << "HELLO_EOF"
class HelloController < ApplicationController
  def index
    render plain: "Hello World!"
  end
end
HELLO_EOF'

# Update routes for Hello World
docker compose exec web bash -c 'cat > config/routes.rb << "ROUTES_EOF"
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
ROUTES_EOF'

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
echo "Hello World endpoint: http://localhost:3000/hello"
echo "Grafana: http://localhost:3001"
echo "Prometheus: http://localhost:9090"