# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.4.0'

# Core dependencies
gem 'async', '~> 2.6'
gem 'async-http', '~> 0.60'
gem 'async-websocket', '~> 0.25'

# Development and testing
group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.57'
  gem 'rubocop-rspec', '~> 2.25'
  gem 'benchmark-ips', '~> 2.12'
end

# Production
group :production do
  gem 'puma', '~> 6.4'
end