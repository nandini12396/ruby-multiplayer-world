#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'async'
require 'async/http/server'
require 'async/websocket/adapters/rack'
require 'json'
require 'logger'
require 'securerandom'

# World State Manager using Ractor
class WorldStateRactor
  def self.spawn
    Ractor.new do
      state = {
        players: {},
        objects: {},
        chat_messages: [],
        world_bounds: { width: 2000, height: 1500 }
      }
      
      loop do
        message = Ractor.receive
        
        case message[:type]
        when :join_player
          player_id = message[:player_id]
          state[:players][player_id] = {
            id: player_id,
            x: rand(100..300),
            y: rand(100..300),
            color: generate_color,
            name: message[:name] || "Player#{player_id[0..7]}",
            last_seen: Time.now.to_f
          }
          Ractor.yield({ type: :player_joined, player: state[:players][player_id] })
          
        when :leave_player
          player_id = message[:player_id]
          removed = state[:players].delete(player_id)
          Ractor.yield({ type: :player_left, player_id: player_id }) if removed
          
        when :move_player
          player_id = message[:player_id]
          if state[:players][player_id]
            bounds = state[:world_bounds]
            new_x = [[message[:x], 0].max, bounds[:width]].min
            new_y = [[message[:y], 0].max, bounds[:height]].min
            
            state[:players][player_id][:x] = new_x
            state[:players][player_id][:y] = new_y
            state[:players][player_id][:last_seen] = Time.now.to_f
            
            Ractor.yield({ 
              type: :player_moved, 
              player_id: player_id, 
              x: new_x, 
              y: new_y 
            })
          end
          
        when :add_chat
          message_obj = {
            id: SecureRandom.uuid,
            player_id: message[:player_id],
            text: message[:text][0..200], # Limit message length
            timestamp: Time.now.to_f
          }
          state[:chat_messages] << message_obj
          state[:chat_messages] = state[:chat_messages].last(50) # Keep last 50 messages
          
          Ractor.yield({ type: :chat_message, message: message_obj })
          
        when :get_state
          Ractor.yield({ 
            type: :world_state, 
            state: {
              players: state[:players].values,
              objects: state[:objects].values,
              chat_messages: state[:chat_messages].last(20)
            }
          })
          
        when :cleanup_inactive
          current_time = Time.now.to_f
          inactive_players = state[:players].select do |_, player|
            current_time - player[:last_seen] > 30 # 30 seconds timeout
          end
          
          inactive_players.each do |player_id, _|
            state[:players].delete(player_id)
            Ractor.yield({ type: :player_left, player_id: player_id })
          end
        end
      end
      
      def generate_color
        colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FECA57', '#FF9FF3', '#54A0FF']
        colors.sample
      end
    end
  end
end

# Connection Manager using Fibers
class ConnectionManager
  def initialize(world_ractor)
    @world_ractor = world_ractor
    @connections = {}
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    
    # Start cleanup task
    Async do
      loop do
        sleep 10
        cleanup_inactive_players
      end
    end
  end
  
  def handle_connection(websocket)
    player_id = SecureRandom.uuid
    @connections[player_id] = websocket
    
    @logger.info "Player #{player_id} connected. Active connections: #{@connections.size}"
    
    # Join player to world
    @world_ractor << { type: :join_player, player_id: player_id }
    
    # Send initial world state
    send_world_state(websocket)
    
    begin
      websocket.each_message do |message|
        handle_message(player_id, message)
      end
    rescue => e
      @logger.error "Connection error for #{player_id}: #{e.message}"
    ensure
      disconnect_player(player_id)
    end
  end
  
  private
  
  def handle_message(player_id, message)
    data = JSON.parse(message)
    
    case data['type']
    when 'move'
      @world_ractor << {
        type: :move_player,
        player_id: player_id,
        x: data['x'].to_f,
        y: data['y'].to_f
      }
      
    when 'chat'
      next if data['text'].to_s.strip.empty?
      
      @world_ractor << {
        type: :add_chat,
        player_id: player_id,
        text: data['text'].to_s.strip
      }
      
    when 'ping'
      send_to_player(player_id, { type: 'pong' })
    end
    
  rescue JSON::ParserError => e
    @logger.warn "Invalid JSON from #{player_id}: #{e.message}"
  end
  
  def send_world_state(websocket)
    @world_ractor << { type: :get_state }
  end
  
  def disconnect_player(player_id)
    @connections.delete(player_id)
    @world_ractor << { type: :leave_player, player_id: player_id }
    @logger.info "Player #{player_id} disconnected. Active connections: #{@connections.size}"
  end
  
  def send_to_player(player_id, data)
    websocket = @connections[player_id]
    return unless websocket
    
    begin
      websocket.write(JSON.generate(data))
    rescue => e
      @logger.warn "Failed to send to #{player_id}: #{e.message}"
      disconnect_player(player_id)
    end
  end
  
  def broadcast(data, exclude_player: nil)
    message = JSON.generate(data)
    
    @connections.each do |player_id, websocket|
      next if player_id == exclude_player
      
      begin
        websocket.write(message)
      rescue => e
        @logger.warn "Failed to broadcast to #{player_id}: #{e.message}"
        disconnect_player(player_id)
      end
    end
  end
  
  def cleanup_inactive_players
    @world_ractor << { type: :cleanup_inactive }
  end
  
  # Handle world state updates from Ractor
  def process_world_updates
    Async do
      loop do
        begin
          update = @world_ractor.take
          
          case update[:type]
          when :player_joined
            broadcast({
              type: 'player_joined',
              player: update[:player]
            })
            
          when :player_left
            broadcast({
              type: 'player_left',
              player_id: update[:player_id]
            })
            
          when :player_moved
            broadcast({
              type: 'player_moved',
              player_id: update[:player_id],
              x: update[:x],
              y: update[:y]
            })
            
          when :chat_message
            broadcast({
              type: 'chat_message',
              message: update[:message]
            })
            
          when :world_state
            # This is typically sent to a specific player, but for demo we'll broadcast
            broadcast({
              type: 'world_state',
              state: update[:state]
            })
          end
          
        rescue => e
          @logger.error "Error processing world update: #{e.message}"
        end
      end
    end
  end
end

# HTTP Server with WebSocket upgrade
class MultiplayerServer
  def initialize(port: 3000)
    @port = port
    @logger = Logger.new(STDOUT)
    @world_ractor = WorldStateRactor.spawn
    @connection_manager = ConnectionManager.new(@world_ractor)
    
    # Start processing world updates
    @connection_manager.process_world_updates
  end
  
  def start
    @logger.info "Starting Multiplayer World Server on port #{@port}"
    
    Async do |task|
      server = Async::HTTP::Server.for(endpoint, protocol: Async::HTTP::Protocol::HTTP11) do |request|
        handle_request(request)
      end
      
      server.run
    end
  end
  
  private
  
  def endpoint
    Async::HTTP::Endpoint.parse("http://localhost:#{@port}")
  end
  
  def handle_request(request)
    case request.path
    when '/'
      serve_client
    when '/ws'
      handle_websocket(request)
    else
      [404, {}, ['Not Found']]
    end
  end
  
  def serve_client
    html_content = generate_client_html
    [200, { 'content-type' => 'text/html' }, [html_content]]
  end
  
  def handle_websocket(request)
    Async::WebSocket::Adapters::Rack.open(request) do |websocket|
      @connection_manager.handle_connection(websocket)
    end
  end
  
  def generate_client_html
    <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>Ruby Multiplayer World</title>
        <style>
            body { margin: 0; font-family: Arial, sans-serif; background: #1a1a2e; color: white; }
            #gameCanvas { border: 2px solid #16213e; background: #0f3460; cursor: crosshair; }
            #ui { position: absolute; top: 10px; left: 10px; z-index: 100; }
            #chat { position: absolute; bottom: 10px; left: 10px; width: 300px; }
            #chatMessages { height: 150px; overflow-y: auto; background: rgba(0,0,0,0.7); padding: 10px; margin-bottom: 5px; }
            #chatInput { width: 100%; padding: 5px; }
            .player { position: absolute; width: 20px; height: 20px; border-radius: 50%; border: 2px solid white; }
            .chat-message { margin: 2px 0; font-size: 12px; }
        </style>
    </head>
    <body>
        <div id="ui">
            <div>Players: <span id="playerCount">0</span></div>
            <div>Position: <span id="position">0, 0</span></div>
        </div>
        
        <canvas id="gameCanvas" width="800" height="600"></canvas>
        
        <div id="chat">
            <div id="chatMessages"></div>
            <input type="text" id="chatInput" placeholder="Type a message..." maxlength="200">
        </div>
        
        <script>
            class MultiplayerWorld {
                constructor() {
                    this.canvas = document.getElementById('gameCanvas');
                    this.ctx = this.canvas.getContext('2d');
                    this.players = new Map();
                    this.myPlayerId = null;
                    this.mousePos = { x: 0, y: 0 };
                    
                    this.setupWebSocket();
                    this.setupEventListeners();
                    this.startGameLoop();
                }
                
                setupWebSocket() {
                    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                    this.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);
                    
                    this.ws.onopen = () => console.log('Connected to server');
                    this.ws.onmessage = (event) => this.handleMessage(JSON.parse(event.data));
                    this.ws.onclose = () => setTimeout(() => location.reload(), 1000);
                }
                
                setupEventListeners() {
                    this.canvas.addEventListener('mousemove', (e) => {
                        const rect = this.canvas.getBoundingClientRect();
                        this.mousePos.x = e.clientX - rect.left;
                        this.mousePos.y = e.clientY - rect.top;
                        
                        this.sendMove(this.mousePos.x, this.mousePos.y);
                        document.getElementById('position').textContent = 
                            `${Math.round(this.mousePos.x)}, ${Math.round(this.mousePos.y)}`;
                    });
                    
                    const chatInput = document.getElementById('chatInput');
                    chatInput.addEventListener('keypress', (e) => {
                        if (e.key === 'Enter' && chatInput.value.trim()) {
                            this.sendChat(chatInput.value.trim());
                            chatInput.value = '';
                        }
                    });
                }
                
                handleMessage(data) {
                    switch (data.type) {
                        case 'world_state':
                            this.handleWorldState(data.state);
                            break;
                        case 'player_joined':
                            this.players.set(data.player.id, data.player);
                            this.updatePlayerCount();
                            break;
                        case 'player_left':
                            this.players.delete(data.player_id);
                            this.updatePlayerCount();
                            break;
                        case 'player_moved':
                            const player = this.players.get(data.player_id);
                            if (player) {
                                player.x = data.x;
                                player.y = data.y;
                            }
                            break;
                        case 'chat_message':
                            this.addChatMessage(data.message);
                            break;
                    }
                }
                
                handleWorldState(state) {
                    this.players.clear();
                    state.players.forEach(player => {
                        this.players.set(player.id, player);
                    });
                    
                    state.chat_messages.forEach(msg => {
                        this.addChatMessage(msg);
                    });
                    
                    this.updatePlayerCount();
                }
                
                sendMove(x, y) {
                    if (this.ws.readyState === WebSocket.OPEN) {
                        this.ws.send(JSON.stringify({ type: 'move', x, y }));
                    }
                }
                
                sendChat(text) {
                    if (this.ws.readyState === WebSocket.OPEN) {
                        this.ws.send(JSON.stringify({ type: 'chat', text }));
                    }
                }
                
                addChatMessage(message) {
                    const chatMessages = document.getElementById('chatMessages');
                    const player = this.players.get(message.player_id);
                    const playerName = player ? player.name : 'Unknown';
                    
                    const div = document.createElement('div');
                    div.className = 'chat-message';
                    div.innerHTML = `<strong>${playerName}:</strong> ${message.text}`;
                    chatMessages.appendChild(div);
                    chatMessages.scrollTop = chatMessages.scrollHeight;
                }
                
                updatePlayerCount() {
                    document.getElementById('playerCount').textContent = this.players.size;
                }
                
                startGameLoop() {
                    const render = () => {
                        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
                        
                        // Draw players
                        this.players.forEach((player) => {
                            this.ctx.fillStyle = player.color;
                            this.ctx.beginPath();
                            this.ctx.arc(player.x, player.y, 10, 0, Math.PI * 2);
                            this.ctx.fill();
                            
                            // Draw player name
                            this.ctx.fillStyle = 'white';
                            this.ctx.font = '12px Arial';
                            this.ctx.textAlign = 'center';
                            this.ctx.fillText(player.name, player.x, player.y - 15);
                        });
                        
                        requestAnimationFrame(render);
                    };
                    render();
                }
            }
            
            // Start the game
            new MultiplayerWorld();
        </script>
    </body>
    </html>
    HTML
  end
end

# Main execution
if __FILE__ == $0
  port = ENV['PORT']&.to_i || 3000
  server = MultiplayerServer.new(port: port)
  server.start
end