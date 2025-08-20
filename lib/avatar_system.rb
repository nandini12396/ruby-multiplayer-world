# frozen_string_literal: true

# Avatar system for multiplayer world
class AvatarSystem
  AVATAR_TYPES = {
    warrior: {
      emoji: '⚔️',
      color: '#FF6B6B',
      shape: 'circle',
      size: 16,
      speed: 1.2,
      description: 'Brave warrior with high speed'
    },
    mage: {
      emoji: '🔮',
      color: '#9B59B6',
      shape: 'star',
      size: 14,
      speed: 0.9,
      description: 'Mystical mage with magical powers'
    },
    archer: {
      emoji: '🏹',
      color: '#2ECC71',
      shape: 'triangle',
      size: 15,
      speed: 1.1,
      description: 'Swift archer with precise aim'
    },
    knight: {
      emoji: '🛡️',
      color: '#3498DB',
      shape: 'square',
      size: 18,
      speed: 0.8,
      description: 'Armored knight with strong defense'
    },
    rogue: {
      emoji: '🗡️',
      color: '#E67E22',
      shape: 'diamond',
      size: 12,
      speed: 1.4,
      description: 'Stealthy rogue with quick movements'
    },
    healer: {
      emoji: '💚',
      color: '#1ABC9C',
      shape: 'heart',
      size: 14,
      speed: 1.0,
      description: 'Healing support with balanced stats'
    }
  }.freeze

  AVATAR_ACCESSORIES = {
    hat: ['🎩', '👑', '🧢', '⛑️', '🎓'],
    weapon: ['⚔️', '🏹', '🔨', '🪓', '🏒'],
    pet: ['🐱', '🐶', '🦊', '🐺', '🦅'],
    aura: ['✨', '🔥', '❄️', '⚡', '🌟']
  }.freeze

  class Avatar
    attr_reader :id, :type, :emoji, :color, :shape, :size, :speed, :accessories, :stats

    def initialize(player_id, type: nil, accessories: {})
      @id = player_id
      @type = type || AVATAR_TYPES.keys.sample
      @avatar_data = AVATAR_TYPES[@type]
      
      @emoji = @avatar_data[:emoji]
      @color = @avatar_data[:color]
      @shape = @avatar_data[:shape]
      @size = @avatar_data[:size]
      @speed = @avatar_data[:speed]
      
      @accessories = generate_accessories(accessories)
      @stats = calculate_stats
    end

    def to_h
      {
        id: @id,
        type: @type,
        emoji: @emoji,
        color: @color,
        shape: @shape,
        size: @size,
        speed: @speed,
        accessories: @accessories,
        stats: @stats,
        description: @avatar_data[:description]
      }
    end

    def display_name
      accessory_display = @accessories.values.join('')
      "#{@emoji}#{accessory_display}"
    end

    private

    def generate_accessories(custom_accessories = {})
      accessories = {}
      
      # Random chance for each accessory type
      AVATAR_ACCESSORIES.each do |type, options|
        if custom_accessories[type]
          accessories[type] = custom_accessories[type]
        elsif rand < 0.3  # 30% chance for random accessory
          accessories[type] = options.sample
        end
      end
      
      accessories
    end

    def calculate_stats
      base_stats = {
        health: 100,
        attack: 50,
        defense: 50,
        magic: 50
      }

      # Modify stats based on avatar type
      case @type
      when :warrior
        base_stats[:attack] += 20
        base_stats[:health] += 10
      when :mage
        base_stats[:magic] += 25
        base_stats[:defense] -= 10
      when :archer
        base_stats[:attack] += 15
        base_stats[:defense] += 5
      when :knight
        base_stats[:defense] += 25
        base_stats[:health] += 15
        base_stats[:attack] -= 5
      when :rogue
        base_stats[:attack] += 10
        base_stats[:defense] -= 15
      when :healer
        base_stats[:magic] += 15
        base_stats[:health] += 20
      end

      # Accessory bonuses
      @accessories.each do |type, _|
        case type
        when :hat
          base_stats[:magic] += 5
        when :weapon
          base_stats[:attack] += 10
        when :pet
          base_stats[:health] += 5
        when :aura
          base_stats[:magic] += 8
        end
      end

      base_stats
    end
  end

  class << self
    def create_avatar(player_id, type: nil, accessories: {})
      Avatar.new(player_id, type: type, accessories: accessories)
    end

    def random_avatar(player_id)
      type = AVATAR_TYPES.keys.sample
      accessories = generate_random_accessories
      Avatar.new(player_id, type: type, accessories: accessories)
    end

    def avatar_types
      AVATAR_TYPES.keys
    end

    def avatar_info(type)
      AVATAR_TYPES[type]
    end

    def available_accessories
      AVATAR_ACCESSORIES
    end

    private

    def generate_random_accessories
      accessories = {}
      AVATAR_ACCESSORIES.each do |type, options|
        accessories[type] = options.sample if rand < 0.4
      end
      accessories
    end
  end
end