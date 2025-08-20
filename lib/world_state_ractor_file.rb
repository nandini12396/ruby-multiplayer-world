# frozen_string_literal: true

require_relative 'avatar_system'

# World State Manager using Ractor
class WorldStateRactor
  def self.spawn
    Ractor.new do
      state = {
        players: {},
        world_objects: {},
        chat_messages: [],
        world_bounds: { width: 2000, height: 1500 },
        game_stats: {
          total_players_joined: 0,
          messages_sent: 0,
          uptime_start: Time.now.to_f
        }
      }
      
      loop do
        message = Ractor.receive
        
        case message[:type]
        when :join_player
          handle_player_join(state, message)
          
        when :leave_player
          handle_player_leave(state, message)
          
        when :move_player
          handle_player_move(state, message)
          
        when :update_avatar
          handle_avatar_update(state, message)
          
        when :add_chat
          handle_chat_message(state, message)
          
        when :get_state
          handle_get_state(state, message)
          
        when :cleanup_inactive
          handle_cleanup_inactive(state, message)
          
        when :get_stats
          handle_get_stats(state, message)
          
        when :spawn_world_object
          handle_spawn_world_object(state, message)
        end
      end
      
      # Helper methods defined in Ractor scope
      def handle_player_join(state, message)
        player_id = message[:player_id]
        avatar_type = message[:avatar_type]
        avatar_accessories = message[:avatar_accessories] || {}
        
        # Create avatar
        avatar = AvatarSystem.create_avatar(
          player_id, 
          type: avatar_type&.to_sym, 
          accessories: avatar_accessories
        )
        
        # Create player with avatar
        player = {
          id: player_id,
          x: rand(100..300),
          y: rand(100..300),
          name: message[:name] || generate_player_name,
          avatar: avatar.to_h,
          last_seen: Time.now.to_f,
          joined_at: Time.now.to_f
        }
        
        state[:players][player_id] = player
        state[:game_stats][:total_players_joined] += 1
        
        Ractor.yield({ 
          type: :player_joined, 
          player: player,
          total_players: state[:players].size
        })
      end
      
      def handle_player_leave(state, message)
        player_id = message[:player_id]
        removed_player = state[:players].delete(player_id)
        
        if removed_player
          Ractor.yield({ 
            type: :player_left, 
            player_id: player_id,
            player_name: removed_player[:name],
            total_players: state[:players].size
          })
        end
      end
      
      def handle_player_move(state, message)
        player_id = message[:player_id]
        player = state[:players][player_id]
        
        return unless player
        
        bounds = state[:world_bounds]
        avatar_speed = player[:avatar][:speed] || 1.0
        
        # Apply avatar speed modifier
        new_x = [[message[:x] * avatar_speed, 0].max, bounds[:width]].min
        new_y = [[message[:y] * avatar_speed, 0].max, bounds[:height]].min
        
        player[:x] = new_x
        player[:y] = new_y
        player[:last_seen] = Time.now.to_f
        
        Ractor.yield({ 
          type: :player_moved, 
          player_id: player_id, 
          x: new_x, 
          y: new_y,
          avatar_display: player[:avatar][:emoji]
        })
      end
      
      def handle_avatar_update(state, message)
        player_id = message[:player_id]
        player = state[:players][player_id]
        
        return unless player
        
        # Create new avatar
        new_avatar = AvatarSystem.create_avatar(
          player_id,
          type: message[:avatar_type]&.to_sym,
          accessories: message[:accessories] || {}
        )
        
        player[:avatar] = new_avatar.to_h
        player[:last_seen] = Time.now.to_f
        
        Ractor.yield({
          type: :avatar_updated,
          player_id: player_id,
          avatar: player[:avatar]
        })
      end
      
      def handle_chat_message(state, message)
        player = state[:players][message[:player_id]]
        return unless player
        
        message_obj = {
          id: SecureRandom.uuid,
          player_id: message[:player_id],
          player_name: player[:name],
          avatar_emoji: player[:avatar][:emoji],
          text: message[:text][0..200], # Limit message length
          timestamp: Time.now.to_f
        }
        
        state[:chat_messages] << message_obj
        state[:chat_messages] = state[:chat_messages].last(50) # Keep last 50 messages
        state[:game_stats][:messages_sent] += 1
        
        Ractor.yield({ type: :chat_message, message: message_obj })
      end
      
      def handle_get_state(state, message)
        uptime = Time.now.to_f - state[:game_stats][:uptime_start]
        
        world_state = {
          players: state[:players].values,
          world_objects: state[:world_objects].values,
          chat_messages: state[:chat_messages].last(20),
          world_bounds: state[:world_bounds],
          game_stats: state[:game_stats].merge(uptime: uptime.round(2))
        }
        
        Ractor.yield({ type: :world_state, state: world_state })
      end
      
      def handle_cleanup_inactive(state, message)
        current_time = Time.now.to_f
        inactive_threshold = 30 # 30 seconds timeout
        
        inactive_players = state[:players].select do |_, player|
          current_time - player[:last_seen] > inactive_threshold
        end
        
        inactive_players.each do |player_id, player|
          state[:players].delete(player_id)
          Ractor.yield({ 
            type: :player_left, 
            player_id: player_id,
            player_name: player[:name],
            reason: 'inactive'
          })
        end
      end
      
      def handle_get_stats(state, message)
        uptime = Time.now.to_f - state[:game_stats][:uptime_start]
        
        stats = {
          active_players: state[:players].size,
          total_messages: state[:game_stats][:messages_sent],
          total_players_joined: state[:game_stats][:total_players_joined],
          uptime_seconds: uptime.round(2),
          world_objects: state[:world_objects].size,
          memory_usage: get_memory_usage
        }
        
        Ractor.yield({ type: :game_stats, stats: stats })
      end
      
      def handle_spawn_world_object(state, message)
        object_id = SecureRandom.uuid
        world_object = {
          id: object_id,
          type: message[:object_type] || 'treasure',
          x: rand(50..state[:world_bounds][:width] - 50),
          y: rand(50..state[:world_bounds][:height] - 50),
          emoji: get_object_emoji(message[:object_type]),
          created_at: Time.now.to_f
        }
        
        state[:world_objects][object_id] = world_object
        
        Ractor.yield({
          type: :world_object_spawned,
          object: world_object
        })
      end
      
      def generate_player_name
        adjectives = %w[Swift Brave Clever Mighty Noble Wise Ancient Mystic Bold Fierce]
        nouns = %w[Warrior Mage Archer Knight Rogue Healer Dragon Phoenix Wolf Eagle]
        "#{adjectives.sample}#{nouns.sample}#{rand(100..999)}"
      end
      
      def get_object_emoji(type)
        case type
        when 'treasure' then '💎'
        when 'food' then '🍎'
        when 'potion' then '🧪'
        when 'weapon' then '⚔️'
        when 'shield' then '🛡️'
        else '✨'
        end
      end
      
      def get_memory_usage
        # Simple memory usage estimate (Ruby doesn't have direct access to process memory in Ractor)
        ObjectSpace.count_objects[:TOTAL] / 1000.0
      end
    end
  end
end