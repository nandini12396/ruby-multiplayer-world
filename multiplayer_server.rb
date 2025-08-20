#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'async'
require 'async/http/server'
require 'async/websocket/adapters/rack'
require 'json'
require 'logger'
require 'securerandom'

# Load application components
require_relative 'lib/avatar_system'
require_relative 'lib/world_state_ractor'
require_relative 'lib/connection_manager'
require_relative 'lib/multiplayer_server'

# Main execution
if __FILE__ == $0
  port = ENV['PORT']&.to_i || 3000
  server = MultiplayerServer.new(port: port)
  server.start
end