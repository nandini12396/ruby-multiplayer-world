# frozen_string_literal: true

# HTTP Server with WebSocket upgrade
class MultiplayerServer
  def initialize(port: 3000)
    @port = port
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    
    initialize_game_systems
    setup_signal_handlers
  end
  
  def start
    @logger.info "🚀 Starting Ruby Multiplayer World Server"
    @logger.info "📡 Port: #{@port}"
    @logger.info "💎 Ruby Version: #{RUBY_VERSION}"
    @logger.info "⚡ Ractor Support: #{defined?(Ractor) ? 'Yes' : 'No'}"
    @logger.info "🧵 Fiber Support: #{defined?(Fiber) ? 'Yes' : 'No'}"
    @logger.info "🌍 World Bounds: #{@world_bounds[:width]}x#{@world_bounds[:height]}"
    
    Async do |task|
      # Start world update processor
      task.async { @connection_manager.process_world_updates }
      
      # Start HTTP server
      server = Async::HTTP::Server.for(endpoint, protocol: Async::HTTP::Protocol::HTTP11) do |request|
        handle_request(request)
      end
      
      @logger.info "✅ Server running at http://localhost:#{@port}"
      @logger.info "🎮 Open your browser and start playing!"
      
      server.run
    end
  end
  
  def stop
    @logger.info "🛑 Shutting down server..."
    @world_ractor&.close rescue nil
  end
  
  private
  
  def initialize_game_systems
    @world_bounds = { width: 1200, height: 800 }
    @world_ractor = WorldStateRactor.spawn
    @connection_manager = ConnectionManager.new(@world_ractor)
    @server_start_time = Time.now
  end
  
  def setup_signal_handlers
    Signal.trap('INT') { stop; exit }
    Signal.trap('TERM') { stop; exit }
  end
  
  def endpoint
    Async::HTTP::Endpoint.parse("http://localhost:#{@port}")
  end
  
  def handle_request(request)
    case request.path
    when '/'
      serve_client
    when '/ws'
      handle_websocket(request)
    when '/api/stats'
      serve_stats
    when '/api/avatars'
      serve_avatar_info
    else
      [404, { 'content-type' => 'application/json' }, [JSON.generate({ error: 'Not Found' })]]
    end
  end
  
  def serve_client
    html_content = generate_client_html
    [200, { 'content-type' => 'text/html; charset=utf-8' }, [html_content]]
  end
  
  def serve_stats
    stats = @connection_manager.get_connection_stats
    server_stats = {
      uptime: (Time.now - @server_start_time).round(2),
      ruby_version: RUBY_VERSION,
      server_time: Time.now.to_f
    }.merge(stats)
    
    [200, { 'content-type' => 'application/json' }, [JSON.generate(server_stats)]]
  end
  
  def serve_avatar_info
    avatar_info = {
      types: AvatarSystem.avatar_types.map { |type| 
        { name: type, info: AvatarSystem.avatar_info(type) }
      },
      accessories: AvatarSystem.available_accessories
    }
    
    [200, { 'content-type' => 'application/json' }, [JSON.generate(avatar_info)]]
  end
  
  def handle_websocket(request)
    Async::WebSocket::Adapters::Rack.open(request) do |websocket|
      @connection_manager.handle_connection(websocket)
    end
  end
  
  def generate_client_html
    <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Ruby Multiplayer World - Avatar System</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            
            body { 
                font-family: 'Segoe UI', Arial, sans-serif; 
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
                color: white; 
                overflow: hidden;
                height: 100vh;
            }
            
            .game-container {
                display: flex;
                height: 100vh;
            }
            
            .sidebar {
                width: 300px;
                background: rgba(0,0,0,0.8);
                border-right: 2px solid #4ECDC4;
                padding: 20px;
                overflow-y: auto;
            }
            
            .main-game {
                flex: 1;
                position: relative;
            }
            
            #gameCanvas { 
                width: 100%;
                height: 100%;
                background: linear-gradient(45deg, #0f3460 0%, #1a1a2e 100%);
                cursor: crosshair; 
                display: block;
            }
            
            .ui-panel {
                position: absolute;
                top: 20px;
                right: 20px;
                background: rgba(0,0,0,0.9);
                padding: 15px;
                border-radius: 10px;
                border: 1px solid #4ECDC4;
                min-width: 200px;
            }
            
            .chat-panel {
                position: absolute;
                bottom: 20px;
                left: 20px;
                width: 350px;
                background: rgba(0,0,0,0.9);
                border-radius: 10px;
                border: 1px solid #FF6B6B;
                max-height: 250px;
                display: flex;
                flex-direction: column;
            }
            
            #chatMessages { 
                height: 180px; 
                overflow-y: auto; 
                padding: 15px; 
                border-bottom: 1px solid #333;
                flex: 1;
            }
            
            #chatInput { 
                width: calc(100% - 20px); 
                padding: 10px; 
                background: rgba(255,255,255,0.1);
                border: none;
                color: white;
                border-radius: 0 0 9px 9px;
                outline: none;
            }
            
            .avatar-selector {
                margin-bottom: 20px;
            }
            
            .avatar-grid {
                display: grid;
                grid-template-columns: repeat(3, 1fr);
                gap: 10px;
                margin: 10px 0;
            }
            
            .avatar-option {
                padding: 10px;
                background: rgba(255,255,255,0.1);
                border: 2px solid transparent;
                border-radius: 8px;
                cursor: pointer;
                text-align: center;
                transition: all 0.3s ease;
            }
            
            .avatar-option:hover {
                background: rgba(255,255,255,0.2);
                border-color: #4ECDC4;
            }
            
            .avatar-option.selected {
                background: rgba(78, 205, 196, 0.3);
                border-color: #4ECDC4;
            }
            
            .avatar-emoji {
                font-size: 24px;
                display: block;
                margin-bottom: 5px;
            }
            
            .avatar-name {
                font-size: 12px;
                color: #ccc;
            }
            
            .accessories {
                margin-top: 15px;
            }
            
            .accessory-group {
                margin-bottom: 10px;
            }
            
            .accessory-options {
                display: flex;
                gap: 5px;
                flex-wrap: wrap;
            }
            
            .accessory-item {
                padding: 5px 8px;
                background: rgba(255,255,255,0.1);
                border: 1px solid transparent;
                border-radius: 5px;
                cursor: pointer;
                font-size: 16px;
                transition: all 0.2s ease;
            }
            
            .accessory-item:hover {
                background: rgba(255,255,255,0.2);
            }
            
            .accessory-item.selected {
                background: rgba(78, 205, 196, 0.3);
                border-color: #4ECDC4;
            }
            
            .stats-panel {
                margin-top: 20px;
                font-size: 12px;
                color: #aaa;
            }
            
            .stat-row {
                display: flex;
                justify-content: space-between;
                margin: 5px 0;
            }
            
            .join-button {
                width: 100%;
                padding: 15px;
                background: linear-gradient(45deg, #4ECDC4, #45B7D1);
                border: none;
                border-radius: 10px;
                color: white;
                font-size: 16px;
                font-weight: bold;
                cursor: pointer;
                margin-top: 20px;
                transition: all 0.3s ease;
            }
            
            .join-button:hover {
                background: linear-gradient(45deg, #45B7D1, #4ECDC4);
                transform: translateY(-2px);
            }
            
            .join-button:disabled {
                opacity: 0.5;
                cursor: not-allowed;
                transform: none;
            }
            
            .player-name-input {
                width: 100%;
                padding: 10px;
                background: rgba(255,255,255,0.1);
                border: 2px solid #4ECDC4;
                border-radius: 5px;
                color: white;
                margin-bottom: 15px;
                outline: none;
            }
            
            .player-name-input::placeholder {
                color: rgba(255,255,255,0.6);
            }
            
            .loading {
                text-align: center;
                padding: 20px;
                color: #4ECDC4;
            }
            
            .error {
                background: rgba(255, 107, 107, 0.2);
                border: 1px solid #FF6B6B;
                padding: 10px;
                border-radius: 5px;
                margin: 10px 0;
                color: #FF6B6B;
            }
            
            @keyframes float {
                0%, 100% { transform: translateY(0px); }
                50% { transform: translateY(-5px); }
            }
            
            .world-object {
                position: absolute;
                font-size: 20px;
                animation: float 3s ease-in-out infinite;
                pointer-events: none;
                text-shadow: 0 0 10px rgba(255,255,255,0.5);
            }
            
            .player-indicator {
                position: absolute;
                pointer-events: none;
                transition: all 0.1s ease;
            }
            
            .player-avatar {
                font-size: 20px;
                text-shadow: 0 0 10px rgba(255,255,255,0.8);
            }
            
            .player-name {
                position: absolute;
                top: -25px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(0,0,0,0.8);
                padding: 2px 6px;
                border-radius: 3px;
                font-size: 10px;
                white-space: nowrap;
                color: white;
            }
            
            .chat-message { 
                margin: 3px 0; 
                font-size: 13px;
                line-height: 1.4;
                word-wrap: break-word;
            }
            
            .chat-avatar {
                display: inline-block;
                margin-right: 5px;
            }
            
            h3 {
                color: #4ECDC4;
                margin-bottom: 15px;
                font-size: 18px;
            }
            
            h4 {
                color: #FF6B6B;
                margin-bottom: 8px;
                font-size: 14px;
            }
        </style>
    </head>
    <body>
        <div class="game-container">
            <!-- Avatar Selection Sidebar -->
            <div class="sidebar">
                <h3>🎮 Create Your Avatar</h3>
                
                <input type="text" class="player-name-input" id="playerName" 
                       placeholder="Enter your name..." maxlength="20">
                
                <div class="avatar-selector">
                    <h4>Choose Avatar Type:</h4>
                    <div class="avatar-grid" id="avatarGrid">
                        <div class="loading">Loading avatars...</div>
                    </div>
                </div>
                
                <div class="accessories">
                    <h4>Accessories (Optional):</h4>
                    <div id="accessoryGroups"></div>
                </div>
                
                <button class="join-button" id="joinButton" disabled>
                    Join World
                </button>
                
                <div class="stats-panel" id="avatarStats">
                    <h4>Avatar Stats:</h4>
                    <div class="stat-row">
                        <span>Health:</span>
                        <span id="statHealth">--</span>
                    </div>
                    <div class="stat-row">
                        <span>Attack:</span>
                        <span id="statAttack">--</span>
                    </div>
                    <div class="stat-row">
                        <span>Defense:</span>
                        <span id="statDefense">--</span>
                    </div>
                    <div class="stat-row">
                        <span>Magic:</span>
                        <span id="statMagic">--</span>
                    </div>
                    <div class="stat-row">
                        <span>Speed:</span>
                        <span id="statSpeed">--</span>
                    </div>
                </div>
                
                <div class="error" id="errorMessage" style="display: none;"></div>
            </div>
            
            <!-- Main Game Area -->
            <div class="main-game">
                <div class="ui-panel">
                    <div>🎯 Players: <span id="playerCount">0</span></div>
                    <div>📍 Position: <span id="position">0, 0</span></div>
                    <div>⚡ Latency: <span id="latency">--ms</span></div>
                    <div>🔄 FPS: <span id="fps">60</span></div>
                </div>
                
                <canvas id="gameCanvas"></canvas>
                
                <div class="chat-panel" style="display: none;" id="chatPanel">
                    <div id="chatMessages"></div>
                    <input type="text" id="chatInput" placeholder="Type a message..." maxlength="200">
                </div>
            </div>
        </div>
        
        <script>
            class AvatarMultiplayerWorld {
                constructor() {
                    this.canvas = document.getElementById('gameCanvas');
                    this.ctx = this.canvas.getContext('2d');
                    this.players = new Map();
                    this.worldObjects = new Map();
                    this.myPlayerId = null;
                    this.mousePos = { x: 0, y: 0 };
                    this.selectedAvatar = null;
                    this.selectedAccessories = {};
                    this.gameJoined = false;
                    this.pingStart = 0;
                    this.latency = 0;
                    
                    this.resizeCanvas();
                    this.loadAvatarOptions();
                    this.setupEventListeners();
                    
                    window.addEventListener('resize', () => this.resizeCanvas());
                }
                
                resizeCanvas() {
                    const container = this.canvas.parentElement;
                    this.canvas.width = container.clientWidth;
                    this.canvas.height = container.clientHeight;
                }
                
                async loadAvatarOptions() {
                    try {
                        const response = await fetch('/api/avatars');
                        const data = await response.json();
                        this.renderAvatarOptions(data);
                    } catch (error) {
                        this.showError('Failed to load avatar options');
                        console.error('Avatar loading error:', error);
                    }
                }
                
                renderAvatarOptions(data) {
                    const avatarGrid = document.getElementById('avatarGrid');
                    avatarGrid.innerHTML = '';
                    
                    data.types.forEach(type => {
                        const option = document.createElement('div');
                        option.className = 'avatar-option';
                        option.dataset.type = type.name;
                        
                        option.innerHTML = \`
                            <span class="avatar-emoji">\${type.info.emoji}</span>
                            <span class="avatar-name">\${type.name}</span>
                        \`;
                        
                        option.addEventListener('click', () => this.selectAvatar(type));
                        avatarGrid.appendChild(option);
                    });
                    
                    this.renderAccessoryOptions(data.accessories);
                }
                
                renderAccessoryOptions(accessories) {
                    const container = document.getElementById('accessoryGroups');
                    container.innerHTML = '';
                    
                    Object.entries(accessories).forEach(([type, options]) => {
                        const group = document.createElement('div');
                        group.className = 'accessory-group';
                        
                        const title = document.createElement('div');
                        title.textContent = type.charAt(0).toUpperCase() + type.slice(1) + ':';
                        title.style.fontSize = '12px';
                        title.style.color = '#ccc';
                        title.style.marginBottom = '5px';
                        
                        const optionsDiv = document.createElement('div');
                        optionsDiv.className = 'accessory-options';
                        
                        options.forEach(option => {
                            const item = document.createElement('div');
                            item.className = 'accessory-item';
                            item.textContent = option;
                            item.dataset.type = type;
                            item.dataset.value = option;
                            
                            item.addEventListener('click', () => this.selectAccessory(type, option, item));
                            optionsDiv.appendChild(item);
                        });
                        
                        group.appendChild(title);
                        group.appendChild(optionsDiv);
                        container.appendChild(group);
                    });
                }
                
                selectAvatar(type) {
                    // Remove previous selection
                    document.querySelectorAll('.avatar-option.selected').forEach(el => {
                        el.classList.remove('selected');
                    });
                    
                    // Select new avatar
                    document.querySelector(\`[data-type="\${type.name}"]\`).classList.add('selected');
                    this.selectedAvatar = type.name;
                    
                    // Update stats display
                    this.updateStatsDisplay(type.info);
                    
                    // Enable join button if name is entered
                    this.updateJoinButton();
                }
                
                selectAccessory(type, value, element) {
                    // Toggle selection
                    const isSelected = element.classList.contains('selected');
                    
                    // Remove other selections in this category
                    document.querySelectorAll(\`[data-type="\${type}"].selected\`).forEach(el => {
                        el.classList.remove('selected');
                    });
                    
                    if (!isSelected) {
                        element.classList.add('selected');
                        this.selectedAccessories[type] = value;
                    } else {
                        delete this.selectedAccessories[type];
                    }
                    
                    // Update stats if avatar is selected
                    if (this.selectedAvatar) {
                        this.updateStatsPreview();
                    }
                }
                
                updateStatsDisplay(info) {
                    document.getElementById('statHealth').textContent = info.stats?.health || '--';
                    document.getElementById('statAttack').textContent = info.stats?.attack || '--';
                    document.getElementById('statDefense').textContent = info.stats?.defense || '--';
                    document.getElementById('statMagic').textContent = info.stats?.magic || '--';
                    document.getElementById('statSpeed').textContent = info.speed + 'x' || '--';
                }
                
                updateStatsPreview() {
                    // Would calculate modified stats based on accessories
                    // For now, just refresh with base stats
                    if (this.selectedAvatar) {
                        const avatarEl = document.querySelector(\`[data-type="\${this.selectedAvatar}"]\`);
                        if (avatarEl) {
                            // This would show modified stats in a real implementation
                        }
                    }
                }
                
                updateJoinButton() {
                    const button = document.getElementById('joinButton');
                    const nameInput = document.getElementById('playerName');
                    const hasName = nameInput.value.trim().length > 0;
                    const hasAvatar = this.selectedAvatar !== null;
                    
                    button.disabled = !(hasName && hasAvatar) || this.gameJoined;
                    
                    if (this.gameJoined) {
                        button.textContent = 'In Game';
                    } else if (hasName && hasAvatar) {
                        button.textContent = 'Join World';
                    } else {
                        button.textContent = 'Select Name & Avatar';
                    }
                }
                
                setupEventListeners() {
                    // Name input
                    document.getElementById('playerName').addEventListener('input', () => {
                        this.updateJoinButton();
                    });
                    
                    // Join button
                    document.getElementById('joinButton').addEventListener('click', () => {
                        if (!this.gameJoined) {
                            this.joinGame();
                        }
                    });
                    
                    // Mouse movement (only when in game)
                    this.canvas.addEventListener('mousemove', (e) => {
                        if (!this.gameJoined) return;
                        
                        const rect = this.canvas.getBoundingClientRect();
                        this.mousePos.x = (e.clientX - rect.left) * (this.canvas.width / rect.width);
                        this.mousePos.y = (e.clientY - rect.top) * (this.canvas.height / rect.height);
                        
                        this.sendMove(this.mousePos.x, this.mousePos.y);
                        document.getElementById('position').textContent = 
                            \`\${Math.round(this.mousePos.x)}, \${Math.round(this.mousePos.y)}\`;
                    });
                    
                    // Chat input
                    document.getElementById('chatInput').addEventListener('keypress', (e) => {
                        if (e.key === 'Enter' && e.target.value.trim() && this.gameJoined) {
                            this.sendChat(e.target.value.trim());
                            e.target.value = '';
                        }
                    });
                }
                
                joinGame() {
                    const name = document.getElementById('playerName').value.trim();
                    if (!name || !this.selectedAvatar) return;
                    
                    this.setupWebSocket();
                    this.gameJoined = true;
                    this.updateJoinButton();
                    
                    // Show chat panel
                    document.getElementById('chatPanel').style.display = 'flex';
                    
                    // Start game loop
                    this.startGameLoop();
                    
                    // Start ping monitoring
                    this.startPingMonitoring();
                }
                
                setupWebSocket() {
                    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                    this.ws = new WebSocket(\`\${protocol}//\${window.location.host}/ws\`);
                    
                    this.ws.onopen = () => {
                        console.log('Connected to server');
                        this.sendJoinWorld();
                    };
                    
                    this.ws.onmessage = (event) => {
                        this.handleMessage(JSON.parse(event.data));
                    };
                    
                    this.ws.onclose = () => {
                        console.log('Disconnected from server');
                        setTimeout(() => location.reload(), 2000);
                    };
                    
                    this.ws.onerror = (error) => {
                        this.showError('Connection error. Please refresh the page.');
                        console.error('WebSocket error:', error);
                    };
                }
                
                sendJoinWorld() {
                    const name = document.getElementById('playerName').value.trim();
                    this.ws.send(JSON.stringify({
                        type: 'join_world',
                        name: name,
                        avatar_type: this.selectedAvatar,
                        avatar_accessories: this.selectedAccessories
                    }));
                }
                
                sendMove(x, y) {
                    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                        this.ws.send(JSON.stringify({ type: 'move', x, y }));
                    }
                }
                
                sendChat(text) {
                    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                        this.ws.send(JSON.stringify({ type: 'chat', text }));
                    }
                }
                
                sendPing() {
                    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
                        this.pingStart = performance.now();
                        this.ws.send(JSON.stringify({ 
                            type: 'ping', 
                            timestamp: this.pingStart 
                        }));
                    }
                }
                
                handleMessage(data) {
                    switch (data.type) {
                        case 'connection_established':
                            this.myPlayerId = data.player_id;
                            break;
                            
                        case 'world_state':
                            this.handleWorldState(data.state);
                            break;
                            
                        case 'player_joined':
                            this.players.set(data.player.id, data.player);
                            this.updatePlayerCount();
                            this.addSystemMessage(\`\${data.player.avatar.emoji} \${data.player.name} joined the world!\`);
                            break;
                            
                        case 'player_left':
                            this.players.delete(data.player_id);
                            this.updatePlayerCount();
                            if (data.player_name) {
                                this.addSystemMessage(\`👋 \${data.player_name} left the world\`);
                            }
                            break;
                            
                        case 'player_moved':
                            const player = this.players.get(data.player_id);
                            if (player) {
                                player.x = data.x;
                                player.y = data.y;
                            }
                            break;
                            
                        case 'avatar_updated':
                            const avatarPlayer = this.players.get(data.player_id);
                            if (avatarPlayer) {
                                avatarPlayer.avatar = data.avatar;
                            }
                            break;
                            
                        case 'chat_message':
                            this.addChatMessage(data.message);
                            break;
                            
                        case 'world_object_spawned':
                            this.worldObjects.set(data.object.id, data.object);
                            break;
                            
                        case 'pong':
                            this.latency = Math.round(performance.now() - this.pingStart);
                            document.getElementById('latency').textContent = this.latency + 'ms';
                            break;
                    }
                }
                
                handleWorldState(state) {
                    this.players.clear();
                    this.worldObjects.clear();
                    
                    state.players.forEach(player => {
                        this.players.set(player.id, player);
                    });
                    
                    if (state.world_objects) {
                        state.world_objects.forEach(obj => {
                            this.worldObjects.set(obj.id, obj);
                        });
                    }
                    
                    if (state.chat_messages) {
                        state.chat_messages.forEach(msg => {
                            this.addChatMessage(msg);
                        });
                    }
                    
                    this.updatePlayerCount();
                }
                
                addChatMessage(message) {
                    const chatMessages = document.getElementById('chatMessages');
                    const div = document.createElement('div');
                    div.className = 'chat-message';
                    
                    const avatarSpan = document.createElement('span');
                    avatarSpan.className = 'chat-avatar';
                    avatarSpan.textContent = message.avatar_emoji || '👤';
                    
                    const nameSpan = document.createElement('strong');
                    nameSpan.textContent = message.player_name + ': ';
                    nameSpan.style.color = '#4ECDC4';
                    
                    const textSpan = document.createElement('span');
                    textSpan.textContent = message.text;
                    
                    div.appendChild(avatarSpan);
                    div.appendChild(nameSpan);
                    div.appendChild(textSpan);
                    
                    chatMessages.appendChild(div);
                    chatMessages.scrollTop = chatMessages.scrollHeight;
                    
                    // Remove old messages
                    if (chatMessages.children.length > 50) {
                        chatMessages.removeChild(chatMessages.firstChild);
                    }
                }
                
                addSystemMessage(text) {
                    const chatMessages = document.getElementById('chatMessages');
                    const div = document.createElement('div');
                    div.className = 'chat-message';
                    div.style.color = '#FFD700';
                    div.style.fontStyle = 'italic';
                    div.textContent = '🎮 ' + text;
                    
                    chatMessages.appendChild(div);
                    chatMessages.scrollTop = chatMessages.scrollHeight;
                }
                
                updatePlayerCount() {
                    document.getElementById('playerCount').textContent = this.players.size;
                }
                
                startGameLoop() {
                    let lastTime = 0;
                    let frameCount = 0;
                    let lastFpsUpdate = 0;
                    
                    const render = (currentTime) => {
                        const deltaTime = currentTime - lastTime;
                        lastTime = currentTime;
                        
                        // Update FPS counter
                        frameCount++;
                        if (currentTime - lastFpsUpdate >= 1000) {
                            document.getElementById('fps').textContent = frameCount;
                            frameCount = 0;
                            lastFpsUpdate = currentTime;
                        }
                        
                        this.renderGame();
                        requestAnimationFrame(render);
                    };
                    
                    requestAnimationFrame(render);
                }
                
                renderGame() {
                    // Clear canvas
                    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
                    
                    // Draw grid background
                    this.drawGrid();
                    
                    // Draw world objects
                    this.worldObjects.forEach((obj) => {
                        this.ctx.font = '20px Arial';
                        this.ctx.textAlign = 'center';
                        this.ctx.fillText(obj.emoji, obj.x, obj.y);
                    });
                    
                    // Draw players
                    this.players.forEach((player) => {
                        this.drawPlayer(player);
                    });
                }
                
                drawGrid() {
                    this.ctx.strokeStyle = 'rgba(78, 205, 196, 0.1)';
                    this.ctx.lineWidth = 1;
                    
                    const gridSize = 50;
                    
                    for (let x = 0; x <= this.canvas.width; x += gridSize) {
                        this.ctx.beginPath();
                        this.ctx.moveTo(x, 0);
                        this.ctx.lineTo(x, this.canvas.height);
                        this.ctx.stroke();
                    }
                    
                    for (let y = 0; y <= this.canvas.height; y += gridSize) {
                        this.ctx.beginPath();
                        this.ctx.moveTo(0, y);
                        this.ctx.lineTo(this.canvas.width, y);
                        this.ctx.stroke();
                    }
                }
                
                drawPlayer(player) {
                    const isMe = player.id === this.myPlayerId;
                    
                    // Draw avatar emoji
                    this.ctx.font = '24px Arial';
                    this.ctx.textAlign = 'center';
                    
                    // Add glow effect for current player
                    if (isMe) {
                        this.ctx.shadowColor = player.avatar.color;
                        this.ctx.shadowBlur = 15;
                    }
                    
                    // Draw main avatar
                    this.ctx.fillText(player.avatar.display_name || player.avatar.emoji, player.x, player.y);
                    
                    // Reset shadow
                    this.ctx.shadowBlur = 0;
                    
                    // Draw player name
                    this.ctx.font = 'bold 12px Arial';
                    this.ctx.fillStyle = isMe ? '#FFD700' : 'white';
                    this.ctx.strokeStyle = 'black';
                    this.ctx.lineWidth = 3;
                    this.ctx.strokeText(player.name, player.x, player.y - 30);
                    this.ctx.fillText(player.name, player.x, player.y - 30);
                    
                    // Draw health bar for demonstration
                    if (player.avatar.stats) {
                        this.drawHealthBar(player);
                    }
                }
                
                drawHealthBar(player) {
                    const barWidth = 40;
                    const barHeight = 4;
                    const x = player.x - barWidth / 2;
                    const y = player.y - 45;
                    
                    // Background
                    this.ctx.fillStyle = 'rgba(255, 0, 0, 0.3)';
                    this.ctx.fillRect(x, y, barWidth, barHeight);
                    
                    // Health (assuming full health for demo)
                    const healthPercent = 1.0; // Could be dynamic
                    this.ctx.fillStyle = 'rgba(0, 255, 0, 0.8)';
                    this.ctx.fillRect(x, y, barWidth * healthPercent, barHeight);
                    
                    // Border
                    this.ctx.strokeStyle = 'white';
                    this.ctx.lineWidth = 1;
                    this.ctx.strokeRect(x, y, barWidth, barHeight);
                }
                
                startPingMonitoring() {
                    setInterval(() => {
                        this.sendPing();
                    }, 5000); // Ping every 5 seconds
                }
                
                showError(message) {
                    const errorDiv = document.getElementById('errorMessage');
                    errorDiv.textContent = message;
                    errorDiv.style.display = 'block';
                    
                    setTimeout(() => {
                        errorDiv.style.display = 'none';
                    }, 5000);
                }
            }
            
            // Initialize the game when page loads
            document.addEventListener('DOMContentLoaded', () => {
                new AvatarMultiplayerWorld();
            });
        </script>
    </body>
    </html>
    HTML
  end
end