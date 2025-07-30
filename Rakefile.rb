# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc 'Run all tests and linting'
task test: [:rubocop, :spec]

desc 'Start the multiplayer server'
task :server do
  require_relative 'multiplayer_server'
  MultiplayerServer.new.start
end

desc 'Run performance benchmarks'
task :benchmark do
  require 'benchmark/ips'
  require_relative 'multiplayer_server'
  
  puts "Ruby Multiplayer World - Performance Benchmarks"
  puts "Ruby Version: #{RUBY_VERSION}"
  puts "Ractor Support: #{defined?(Ractor) ? 'Yes' : 'No'}"
  puts "Fiber Support: #{defined?(Fiber) ? 'Yes' : 'No'}"
  puts "-" * 50
  
  # Benchmark JSON operations
  sample_data = { type: 'move', x: 150.5, y: 200.3, player_id: 'test123' }
  
  Benchmark.ips do |x|
    x.report('JSON.generate') { JSON.generate(sample_data) }
    x.report('JSON.parse') { JSON.parse('{"type":"move","x":150.5,"y":200.3}') }
    x.compare!
  end
  
  # Benchmark Ractor communication
  puts "\nRactor Communication Benchmark:"
  world_ractor = WorldStateRactor.spawn
  
  Benchmark.ips do |x|
    x.report('Ractor send/receive') do
      world_ractor << { type: :get_state }
      world_ractor.take
    end
    x.compare!
  end
end

desc 'Load test with simulated connections'
task :load_test do
  require 'async'
  require 'async/websocket/client'
  require 'json'
  
  puts "Running load test with 50 simulated connections..."
  
  Async do
    connections = []
    
    50.times do |i|
      connections << Async do
        begin
          endpoint = Async::HTTP::Endpoint.parse('ws://localhost:3000/ws')
          Async::WebSocket::Client.connect(endpoint) do |websocket|
            # Send periodic moves
            10.times do
              websocket.write(JSON.generate({
                type: 'move',
                x: rand(800),
                y: rand(600)
              }))
              sleep(0.1)
            end
            
            # Send a chat message
            websocket.write(JSON.generate({
              type: 'chat',
              text: "Hello from client #{i}!"
            }))
            
            # Listen for a bit
            timeout = 5
            websocket.read do |message|
              data = JSON.parse(message)
              puts "Client #{i} received: #{data['type']}" if i == 0 # Only log first client
              timeout -= 0.1
              break if timeout <= 0
            end
          end
        rescue => e
          puts "Client #{i} error: #{e.message}"
        end
      end
    end
    
    connections.each(&:wait)
    puts "Load test completed!"
  end
end

task default: :test