# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ruby Multiplayer World with Avatars' do
  describe AvatarSystem do
    describe AvatarSystem::Avatar do
      let(:avatar) { AvatarSystem::Avatar.new('test123', type: :warrior) }
      
      it 'creates avatar with correct properties' do
        expect(avatar.id).to eq('test123')
        expect(avatar.type).to eq(:warrior)
        expect(avatar.emoji).to eq('⚔️')
        expect(avatar.color).to eq('#FF6B6B')
        expect(avatar.shape).to eq('circle')
        expect(avatar.speed).to eq(1.2)
      end
      
      it 'calculates stats correctly' do
        stats = avatar.stats
        expect(stats[:health]).to be > 100  # Warrior bonus
        expect(stats[:attack]).to be > 50   # Warrior bonus
        expect(stats[:defense]).to eq(50)   # Base defense
        expect(stats[:magic]).to eq(50)     # Base magic
      end
      
      it 'generates accessories randomly' do
        avatar1 = AvatarSystem::Avatar.new('test1', type: :mage)
        avatar2 = AvatarSystem::Avatar.new('test2', type: :mage)
        
        # Accessories might be different due to randomness
        expect([avatar1.accessories, avatar2.accessories]).to all(be_a(Hash))
      end
      
      it 'applies accessory stat bonuses' do
        avatar_with_weapon = AvatarSystem::Avatar.new('test', type: :knight, accessories: { weapon: '⚔️' })
        avatar_without = AvatarSystem::Avatar.new('test2', type: :knight)
        
        expect(avatar_with_weapon.stats[:attack]).to be > avatar_without.stats[:attack]
      end
    end
    
    describe 'class methods' do
      it 'creates random avatars' do
        avatar = AvatarSystem.random_avatar('random123')
        expect(avatar).to be_a(AvatarSystem::Avatar)
        expect(avatar.id).to eq('random123')
        expect(AvatarSystem.avatar_types).to include(avatar.type)
      end
      
      it 'provides avatar type information' do
        info = AvatarSystem.avatar_info(:mage)
        expect(info[:emoji]).to eq('🔮')
        expect(info[:color]).to eq('#9B59B6')
        expect(info[:description]).to be_a(String)
      end
      
      it 'lists available accessories' do
        accessories = AvatarSystem.available_accessories
        expect(accessories).to have_key(:hat)
        expect(accessories).to have_key(:weapon)
        expect(accessories[:hat]).to be_an(Array)
      end
    end
  end
  
  describe WorldStateRactor do
    let(:world_ractor) { described_class.spawn }
    
    after { world_ractor&.close rescue nil }
    
    it 'handles player joining with avatar' do
      world_ractor << { 
        type: :join_player, 
        player_id: 'test123', 
        name: 'TestWarrior',
        avatar_type: 'warrior',
        avatar_accessories: { weapon: '⚔️' }
      }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:player_joined)
      expect(response[:player][:id]).to eq('test123')
      expect(response[:player][:name]).to eq('TestWarrior')
      expect(response[:player][:avatar][:type]).to eq(:warrior)
      expect(response[:player][:avatar][:emoji]).to eq('⚔️')
      expect(response[:player][:avatar][:accessories][:weapon]).to eq('⚔️')
    end
    
    it 'handles avatar updates' do
      player_id = 'test123'
      
      # Join first
      world_ractor << { type: :join_player, player_id: player_id, avatar_type: 'knight' }
      world_ractor.take
      
      # Update avatar
      world_ractor << { 
        type: :update_avatar, 
        player_id: player_id, 
        avatar_type: 'mage',
        accessories: { hat: '🎩' }
      }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:avatar_updated)
      expect(response[:player_id]).to eq(player_id)
      expect(response[:avatar][:type]).to eq(:mage)
      expect(response[:avatar][:accessories][:hat]).to eq('🎩')
    end
    
    it 'applies avatar speed to movement' do
      player_id = 'test123'
      
      # Join with fast rogue
      world_ractor << { type: :join_player, player_id: player_id, avatar_type: 'rogue' }
      join_response = world_ractor.take
      expect(join_response[:player][:avatar][:speed]).to eq(1.4)
      
      # Move player
      world_ractor << { type: :move_player, player_id: player_id, x: 100, y: 100 }
      move_response = world_ractor.take
      
      # Movement should be modified by speed (though bounds checking might affect this)
      expect(move_response[:type]).to eq(:player_moved)
      expect(move_response[:player_id]).to eq(player_id)
    end
    
    it 'includes avatar emoji in chat messages' do
      player_id = 'test123'
      
      # Join with mage
      world_ractor << { type: :join_player, player_id: player_id, avatar_type: 'mage', name: 'Gandalf' }
      world_ractor.take
      
      # Send chat
      world_ractor << { type: :add_chat, player_id: player_id, text: 'Hello world!' }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:chat_message)
      expect(response[:message][:avatar_emoji]).to eq('🔮')
      expect(response[:message][:player_name]).to eq('Gandalf')
    end
    
    it 'spawns world objects' do
      world_ractor << { type: :spawn_world_object, object_type: 'treasure' }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:world_object_spawned)
      expect(response[:object][:type]).to eq('treasure')
      expect(response[:object][:emoji]).to eq('💎')
      expect(response[:object][:x]).to be_between(50, 1950)
      expect(response[:object][:y]).to be_between(50, 1450)
    end
    
    it 'provides comprehensive game stats' do
      # Add some players and activity
      world_ractor << { type: :join_player, player_id: 'player1', avatar_type: 'warrior' }
      world_ractor.take
      
      world_ractor << { type: :add_chat, player_id: 'player1', text: 'Hello!' }
      world_ractor.take
      
      world_ractor << { type: :get_stats }
      response = world_ractor.take
      
      expect(response[:type]).to eq(:game_stats)
      expect(response[:stats][:active_players]).to eq(1)
      expect(response[:stats][:total_messages]).to eq(1)
      expect(response[:stats][:uptime_seconds]).to be > 0
    end
  end
  
  describe ConnectionManager do
    let(:world_ractor) { WorldStateRactor.spawn }
    let(:connection_manager) { described_class.new(world_ractor) }
    
    after { world_ractor&.close rescue nil }
    
    it 'handles avatar-specific messages' do
      expect do
        connection_manager.send(:handle_message, 'test_player', JSON.generate({
          type: 'change_avatar',
          avatar_type: 'mage',
          accessories: { hat: '🎩' }
        }))
      end.not_to raise_error
    end
    
    it 'provides avatar options to clients' do
      expect do
        connection_manager.send(:send_avatar_options, 'test_player')
      end.not_to raise_error
    end
    
    it 'handles world object spawning requests' do
      expect do
        connection_manager.send(:handle_message, 'test_player', JSON.generate({
          type: 'spawn_object',
          object_type: 'treasure'
        }))
      end.not_to raise_error
    end
    
    it 'tracks connection metadata' do
      metadata = connection_manager.instance_variable_get(:@connection_metadata)
      expect(metadata).to be_a(Hash)
      
      stats = connection_manager.get_connection_stats
      expect(stats).to have_key(:active_connections)
      expect(stats).to have_key(:total_messages_processed)
      expect(stats).to have_key(:messages_per_second)
    end
  end
  
  describe MultiplayerServer do
    let(:server) { described_class.new(port: 0) }
    
    it 'initializes with avatar system' do
      expect(server.instance_variable_get(:@world_ractor)).to be_a(Ractor)
      expect(server.instance_variable_get(:@connection_manager)).to be_a(ConnectionManager)
    end
    
    it 'serves avatar information endpoint' do
      request = double('request')
      allow(request).to receive(:path).and_return('/api/avatars')
      
      response = server.send(:handle_request, request)
      
      expect(response[0]).to eq(200)
      expect(response[1]['content-type']).to eq('application/json')
      
      data = JSON.parse(response[2][0])
      expect(data).to have_key('types')
      expect(data).to have_key('accessories')
    end
    
    it 'serves system stats endpoint' do
      request = double('request')
      allow(request).to receive(:path).and_return('/api/stats')
      
      response = server.send(:handle_request, request)
      
      expect(response[0]).to eq(200)
      expect(response[1]['content-type']).to eq('application/json')
      
      data = JSON.parse(response[2][0])
      expect(data).to have_key('uptime')
      expect(data).to have_key('ruby_version')
      expect(data).to have_key('active_connections')
    end
    
    it 'generates enhanced HTML client with avatar system' do
      html = server.send(:generate_client_html)
      
      expect(html).to include('Avatar System')
      expect(html).to include('avatar-selector')
      expect(html).to include('accessory-options')
      expect(html).to include('AvatarMultiplayerWorld')
      expect(html).to include('loadAvatarOptions')
    end
  end
  
  describe 'Avatar System Integration' do
    it 'handles complete avatar workflow', :focus do
      world_ractor = WorldStateRactor.spawn
      
      # Player joins with custom avatar
      world_ractor << {
        type: :join_player,
        player_id: 'integration_test',
        name: 'TestHero',
        avatar_type: 'knight',
        avatar_accessories: { weapon: '⚔️', hat: '👑' }
      }
      
      join_response = world_ractor.take
      
      # Verify complete avatar data
      avatar = join_response[:player][:avatar]
      expect(avatar[:type]).to eq(:knight)
      expect(avatar[:emoji]).to eq('🛡️')
      expect(avatar[:accessories][:weapon]).to eq('⚔️')
      expect(avatar[:accessories][:hat]).to eq('👑')
      expect(avatar[:stats][:defense]).to be > 50  # Knight has defense bonus
      
      # Update avatar
      world_ractor << {
        type: :update_avatar,
        player_id: 'integration_test',
        avatar_type: 'mage',
        accessories: { aura: '✨' }
      }
      
      update_response = world_ractor.take
      
      # Verify avatar update
      new_avatar = update_response[:avatar]
      expect(new_avatar[:type]).to eq(:mage)
      expect(new_avatar[:emoji]).to eq('🔮')
      expect(new_avatar[:accessories][:aura]).to eq('✨')
      
      # Test movement with new speed
      world_ractor << { type: :move_player, player_id: 'integration_test', x: 200, y: 200 }
      move_response = world_ractor.take
      
      expect(move_response[:type]).to eq(:player_moved)
      
      # Test chat with avatar emoji
      world_ractor << { type: :add_chat, player_id: 'integration_test', text: 'Avatar system works!' }
      chat_response = world_ractor.take
      
      expect(chat_response[:message][:avatar_emoji]).to eq('🔮')
      
      world_ractor.close rescue nil
    end
  end
  
  describe 'Performance with Avatars' do
    it 'handles multiple avatar updates efficiently' do
      world_ractor = WorldStateRactor.spawn
      
      start_time = Time.now
      
      # Create 50 players with different avatars
      avatar_types = AvatarSystem.avatar_types
      50.times do |i|
        world_ractor << {
          type: :join_player,
          player_id: "perf_test_#{i}",
          avatar_type: avatar_types[i % avatar_types.length]
        }
        world_ractor.take
      end
      
      # Update all avatars
      50.times do |i|
        world_ractor << {
          type: :update_avatar,
          player_id: "perf_test_#{i}",
          avatar_type: avatar_types.sample,
          accessories: { hat: AvatarSystem.available_accessories[:hat].sample }
        }
        world_ractor.take
      end
      
      elapsed = Time.now - start_time
      
      # Should handle 100 operations (50 joins + 50 updates) efficiently
      expect(elapsed).to be < 5.0
      
      world_ractor.close rescue nil
    end
  end
end