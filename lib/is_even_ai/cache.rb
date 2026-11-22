# frozen_string_literal: true

module IsEvenAI
  # Thread-safe in-memory store. Any object responding to #read(key) and #write(key, value)
  # (for example Rails.cache) may be used instead via `config.cache = store`.
  class Cache
    DEFAULT_MAX_SIZE = 1_000

    def initialize(max_size: DEFAULT_MAX_SIZE)
      @max_size = max_size
      @store = {}
      @mutex = Mutex.new
    end

    def read(key)
      @mutex.synchronize { @store[key] }
    end

    def write(key, value)
      @mutex.synchronize do
        @store.delete(@store.keys.first) if !@store.key?(key) && @store.size >= @max_size
        @store[key] = value
      end
    end

    def clear
      @mutex.synchronize { @store.clear }
    end

    def size
      @mutex.synchronize { @store.size }
    end

    # Resolves the `config.cache` setting to a store, or nil when caching is off.
    def self.resolve(setting, default:)
      case setting
      when nil, false then nil
      when true then default
      else
        raise ConfigurationError, "config.cache must be true, false, or an object responding to #read and #write" unless setting.respond_to?(:read) && setting.respond_to?(:write)

        setting
      end
    end
  end
end
