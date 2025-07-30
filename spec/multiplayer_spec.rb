# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MultiplayerWorld' do
  describe WorldStateRactor do
    let(:world_ractor) { described_class.spawn }
    
    after { world_ractor&.close rescue nil }
    
    it 'handles player joining' do
      world_ractor << { type: :join_player, player_id: 'test123', name: 'TestPlayer' }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:player_joined)
      expect(response[:player][:id]).to eq('test123')
      expect(response[:player][:name]).to eq('TestPlayer')
      expect(response[:player][:x]).to be_between(100, 300)
      expect(response[:player][:y]).to be_between(100, 300)
    end
    
    it 'handles player movement with bounds checking' do
      player_id = 'test123'
      
      # Join player first
      world_ractor << { type: :join_player, player_id: player_id }
      world_ractor.take # consume join response
      
      # Test normal movement
      world_ractor << { type: :move_player, player_id: player_id, x: 100, y: 200 }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:player_moved)
      expect(response[:x]).to eq(100)
      expect(response[:y]).to eq(200)
      
      # Test bounds checking (negative coordinates)
      world_ractor << { type: :move_player, player_id: player_id, x: -50, y: -100 }
      response = world_ractor.take
      
      expect(response[:x]).to eq(0)
      expect(response[:y]).to eq(0)
      
      # Test bounds checking (exceeding world bounds)
      world_ractor << { type: :move_player, player_id: player_id, x: 3000, y: 2000 }
      response = world_ractor.take
      
      expect(response[:x]).to eq(2000)
      expect(response[:y]).to eq(1500)
    end
    
    it 'handles chat messages with length limiting' do
      player_id = 'test123'
      long_text = 'a' * 300 # Exceeds 200 char limit
      
      world_ractor << { type: :add_chat, player_id: player_id, text: long_text }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:chat_message)
      expect(response[:message][:text].length).to eq(200)
      expect(response[:message][:player_id]).to eq(player_id)
    end
    
    it 'maintains world state correctly' do
      player1 = 'player1'
      player2 = 'player2'
      
      # Add two players
      world_ractor << { type: :join_player, player_id: player1, name: 'Player1' }
      world_ractor.take
      
      world_ractor << { type: :join_player, player_id: player2, name: 'Player2' }
      world_ractor.take
      
      # Get world state
      world_ractor << { type: :get_state }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:world_state)
      expect(response[:state][:players].length).to eq(2)
      expect(response[:state][:players].map { |p| p[:id] }).to contain_exactly(player1, player2)
    end
    
    it 'handles player leaving' do
      player_id = 'test123'
      
      # Join then leave
      world_ractor << { type: :join_player, player_id: player_id }
      world_ractor.take
      
      world_ractor << { type: :leave_player, player_id: player_id }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:player_left)
      expect(response[:player_id]).to eq(player_id)
    end
  end
  
  describe ConnectionManager do
    let(:world_ractor) { WorldStateRactor.spawn }
    let(:connection_manager) { described_class.new(world_ractor) }
    
    after { world_ractor&.close rescue nil }
    
    it 'initializes with empty connections' do
      expect(connection_manager.instance_variable_get(:@connections)).to be_empty
    end
    
    it 'handles JSON parsing errors gracefully' do
      expect do
        connection_manager.send(:handle_message, 'test_player', 'invalid json')
      end.not_to raise_error
    end
  end
  
  describe MultiplayerServer do
    let(:server) { described_class.new(port: 0) } # Use port 0 for testing
    
    it 'initializes correctly' do
      expect(server.instance_variable_get(:@world_ractor)).to be_a(Ractor)
      expect(server.instance_variable_get(:@connection_manager)).to be_a(ConnectionManager)
    end
    
    it 'generates valid HTML client' do
      html = server.send(:generate_client_html)
      
      expect(html).to include('<!DOCTYPE html>')
      expect(html).to include('<canvas id="gameCanvas"')
      expect(html).to include('class MultiplayerWorld')
      expect(html).to include('setupWebSocket()')
    end
    
    it 'handles HTTP requests correctly' do
      # Mock request object
      request = double('request')
      
      allow(request).to receive(:path).and_return('/')
      response = server.send(:handle_request, request)
      
      expect(response[0]).to eq(200) # HTTP 200
      expect(response[1]['content-type']).to eq('text/html')
      
      allow(request).to receive(:path).and_return('/nonexistent')
      response = server.send(:handle_request, request)
      
      expect(response[0]).to eq(404) # HTTP 404
    end
  end
  
  describe 'Race condition handling' do
    it 'handles concurrent player operations safely', :focus do
      world_ractor = WorldStateRactor.spawn
      
      # Simulate concurrent joins
      threads = []
      player_ids = []
      
      10.times do |i|
        threads << Thread.new do
          player_id = "player#{i}"
          player_ids << player_id
          world_ractor << { type: :join_player, player_id: player_id, name: "Player#{i}" }
        end
      end
      
      threads.each(&:join)
      
      # Collect all responses
      responses = []
      10.times do
        responses << world_ractor.