# frozen_string_literal: true

# Connection Manager using Fibers
class ConnectionManager
  def initialize(world_ractor)
    @world_ractor = world_ractor
    @connections = {}
    @connection_metadata = {}
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @message_stats = {
      total_messages: 0,
      messages_per_second: 0,
      last_reset: Time.now
    }
    
    # Start background tasks
    start_background_tasks
  end
  
  def handle_connection(websocket)
    player_id = SecureRandom.uuid
    connection_start = Time.now
    
    @connections[player_id] = websocket
    @connection_metadata[player_id] = {
      connected_at: connection_start,
      last_ping: connection_start,
      messages_sent: 0,
      user_agent: websocket.headers&.[]('user-agent') || 'Unknown'
    }
    
    @logger.info "🎮 Player #{player_id[0..7]} connected from #{get_client_info(websocket)}. Active: #{@connections.size}"
    
    # Send initial connection info
    send_to_player(player_id, {
      type: 'connection_established',
      player_id: player_id,
      server_time: Time.now.to_f
    })
    
    # Request world state for new player
    @world_ractor << { type: :get_state }
    
    begin
      websocket.each_message do |message|
        handle_message(player_id, message)
        update_message_stats
      end
    rescue => e
      @logger.error "💥 Connection error for #{player_id[0..7]}: #{e.message}"
    ensure
      disconnect_player(player_id)
    end
  end
  
  # Process world state updates from Ractor
  def process_world_updates
    Async do
      loop do
        begin
          update = @world_ractor.take
          handle_world_update(update)
        rescue => e
          @logger.error "🔥 Error processing world update: #{e.message}"
          @logger.error e.backtrace.join("\n")
        end
      end
    end
  end
  
  def get_connection_stats
    active_connections = @connections.size
    total_messages = @message_stats[:total_messages]
    avg_connection_time = calculate_avg_connection_time
    
    {
      active_connections: active_connections,
      total_messages_processed: total_messages,
      messages_per_second: @message_stats[:messages_per_second],
      average_connection_duration: avg_connection_time,
      memory_per_connection: estimate_memory_per_connection
    }
  end
  
  private
  
  def handle_message(player_id, message)
    data = JSON.parse(message)
    
    case data['type']
    when 'join_world'
      handle_join_world(player_id, data)
      
    when 'move'
      handle_player_move(player_id, data)
      
    when 'chat'
      handle_chat_message(player_id, data)
      
    when 'change_avatar'
      handle_avatar_change(player_id, data)
      
    when 'ping'
      handle_ping(player_id, data)
      
    when 'get_avatar_options'
      send_avatar_options(player_id)
      
    when 'spawn_object'
      handle_spawn_object(player_id, data)
      
    else
      @logger.warn "🤔 Unknown message type from #{player_id[0..7]}: #{data['type']}"
    end
    
    # Update connection metadata
    @connection_metadata[player_id][:messages_sent] += 1
    
  rescue JSON::ParserError => e
    @logger.warn "📝 Invalid JSON from #{player_id[0..7]}: #{e.message}"
  rescue => e
    @logger.error "⚠️  Error handling message from #{player_id[0..7]}: #{e.message}"
  end
  
  def handle_join_world(player_id, data)
    @world_ractor << {
      type: :join_player,
      player_id: player_id,
      name: data['name'],
      avatar_type: data['avatar_type'],
      avatar_accessories: data['avatar_accessories'] || {}
    }
  end
  
  def handle_player_move(player_id, data)
    return unless data['x'] && data['y']
    
    @world_ractor << {
      type: :move_player,
      player_id: player_id,
      x: data['x'].to_f,
      y: data['y'].to_f
    }
  end
  
  def handle_chat_message(player_id, data)
    return if data['text'].to_s.strip.empty?
    
    @world_ractor << {
      type: :add_chat,
      player_id: player_id,
      text: data['text'].to_s.strip
    }
  end
  
  def handle_avatar_change(player_id, data)
    @world_ractor << {
      type: :update_avatar,
      player_id: player_id,
      avatar_type: data['avatar_type'],
      accessories: data['accessories'] || {}
    }
  end
  
  def handle_ping(player_id, data)
    @connection_metadata[player_id][:last_ping] = Time.now
    send_to_player(player_id, { 
      type: 'pong', 
      timestamp: data['timestamp'],
      server_time: Time.now.to_f
    })
  end
  
  def handle_spawn_object(player_id, data)
    # Only allow certain players to spawn objects (could add permissions)
    @world_ractor << {
      type: :spawn_world_object,
      player_id: player_id,
      object_type: data['object_type']
    }
  end
  
  def send_avatar_options(player_id)
    options = {
      types: AvatarSystem.avatar_types.map { |type| 
        { name: type, info: AvatarSystem.avatar_info(type) }
      },
      accessories: AvatarSystem.available_accessories
    }
    
    send_to_player(player_id, {
      type: 'avatar_options',
      options: options
    })
  end
  
  def handle_world_update(update)
    case update[:type]
    when :player_joined
      broadcast({
        type: 'player_joined',
        player: update[:player],
        total_players: update[:total_players]
      })
      
    when :player_left
      broadcast({
        type: 'player_left',
        player_id: update[:player_id],
        player_name: update[:player_name],
        total_players: update[:total_players]
      })
      
    when :player_moved
      broadcast({
        type: 'player_moved',
        player_id: update[:player_id],
        x: update[:x],
        y: update[:y],
        avatar_display: update[:avatar_display]
      })
      
    when :avatar_updated
      broadcast({
        type: 'avatar_updated',
        player_id: update[:player_id],
        avatar: update[:avatar]
      })
      
    when :chat_message
      broadcast({
        type: 'chat_message',
        message: update[:message]
      })
      
    when :world_state
      broadcast({
        type: 'world_state',
        state: update[:state]
      })
      
    when :world_object_spawned
      broadcast({
        type: 'world_object_spawned',
        object: update[:object]
      })
      
    when :game_stats
      broadcast({
        type: 'game_stats',
        stats: update[:stats]
      })
    end
  end
  
  def disconnect_player(player_id)
    @connections.delete(player_id)
    @connection_metadata.delete(player_id)
    @world_ractor << { type: :leave_player, player_id: player_id }
    
    connection_duration = Time.now - (@connection_metadata.dig(player_id, :connected_at) || Time.now)
    @logger.info "👋 Player #{player_id[0..7]} disconnected after #{connection_duration.round(1)}s. Active: #{@connections.size}"
  end
  
  def send_to_player(player_id, data)
    websocket = @connections[player_id]
    return unless websocket
    
    begin
      websocket.write(JSON.generate(data))
    rescue => e
      @logger.warn "📤 Failed to send to #{player_id[0..7]}: #{e.message}"
      disconnect_player(player_id)
    end
  end
  
  def broadcast(data, exclude_player: nil)
    message = JSON.generate(data)
    failed_connections = []
    
    @connections.each do |player_id, websocket|
      next if player_id == exclude_player
      
      begin
        websocket.write(message)
      rescue => e
        @logger.warn "📡 Failed to broadcast to #{player_id[0..7]}: #{e.message}"
        failed_connections << player_id
      end
    end
    
    # Clean up failed connections
    failed_connections.each { |player_id| disconnect_player(player_id) }
  end
  
  def start_background_tasks
    # Cleanup task
    Async do
      loop do
        sleep 10
        cleanup_inactive_players
        update_performance_stats
      end
    end
    
    # Stats reporting task
    Async do
      loop do
        sleep 30
        report_system_stats
      end
    end
  end
  
  def cleanup_inactive_players
    @world_ractor << { type: :cleanup_inactive }
  end
  
  def update_message_stats
    @message_stats[:total_messages] += 1
    
    # Calculate messages per second every 10 seconds
    if Time.now - @message_stats[:last_reset] >= 10
      @message_stats[:messages_per_second] = @message_stats[:total_messages] / 10.0
      @message_stats[:total_messages] = 0
      @message_stats[:last_reset] = Time.now
    end
  end
  
  def update_performance_stats
    # Request updated game stats from Ractor
    @world_ractor << { type: :get_stats }
  end
  
  def report_system_stats
    stats = get_connection_stats
    @logger.info "📊 System Stats: #{@connections.size} active connections, #{stats[:messages_per_second]} msg/s"
  end
  
  def calculate_avg_connection_time
    return 0 if @connection_metadata.empty?
    
    current_time = Time.now
    total_time = @connection_metadata.values.sum do |metadata|
      current_time - metadata[:connected_at]
    end
    
    (total_time / @connection_metadata.size).round(2)
  end
  
  def estimate_memory_per_connection
    # Rough estimate: each connection has websocket + metadata
    base_memory_kb = 50 # Base WebSocket overhead
    metadata_memory_kb = 5 # Our metadata
    (base_memory_kb + metadata_memory_kb)
  end
  
  def get_client_info(websocket)
    # Extract client information from headers if available
    user_agent = websocket.headers&.[]('user-agent') || 'Unknown'
    user_agent.split(' ').first || 'Unknown'
  end
end