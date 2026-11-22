# frozen_string_literal: true

module IsEvenAI
  class Configuration
    PRIMITIVES = %i[noul choice score].freeze

    DEFAULTS = {
      provider: nil,
      api_key: nil,
      model: nil,
      base_url: nil,
      jev_primitive: :noul,
      yes_threshold: 0.7,
      no_threshold: 0.3,
      strict_confidence: false,
      allow_non_integer: false,
      fallback_provider: nil,
      fallback_options: {},
      on_uncertain: nil,
      cache: false,
      open_timeout: 5,
      read_timeout: 30,
      max_retries: 2,
      fan_out: false
    }.freeze

    # Per-call keyword aliases.
    ALIASES = { primitive: :jev_primitive }.freeze

    API_KEY_ENV = {
      jev: %w[TYPESAFE_API_KEY],
      openai: %w[OPENAI_API_KEY],
      anthropic: %w[ANTHROPIC_API_KEY],
      gemini: %w[GEMINI_API_KEY GOOGLE_API_KEY],
      openai_compatible: %w[OPENAI_API_KEY IS_EVEN_AI_API_KEY]
    }.freeze

    # Order matters: first present key wins when IS_EVEN_AI_PROVIDER is not set.
    DETECTION_ORDER = [
      [:jev, %w[TYPESAFE_API_KEY]],
      [:openai, %w[OPENAI_API_KEY]],
      [:anthropic, %w[ANTHROPIC_API_KEY]],
      [:gemini, %w[GEMINI_API_KEY GOOGLE_API_KEY]],
      [:openai_compatible, %w[IS_EVEN_AI_API_KEY]]
    ].freeze

    attr_accessor(*DEFAULTS.keys)

    def initialize
      DEFAULTS.each { |key, value| public_send(:"#{key}=", value.dup) }
    end

    def initialize_copy(source)
      super
      @fallback_options = source.fallback_options.dup
    end

    # A copy with per-call overrides applied and validated.
    def merge(overrides = {})
      copy = dup
      overrides.each do |key, value|
        key = ALIASES.fetch(key.to_sym, key.to_sym)
        raise ConfigurationError, "Unknown option #{key.inspect}" unless DEFAULTS.key?(key)

        copy.public_send(:"#{key}=", value)
      end
      copy.validate!
      copy
    end

    def validate!
      validate_provider!(provider, "provider")
      validate_provider!(fallback_provider, "fallback_provider")
      raise ConfigurationError, "Unknown jev_primitive #{jev_primitive.inspect}; expected one of #{PRIMITIVES.join(", ")}" unless PRIMITIVES.include?(jev_primitive&.to_sym)

      validate_thresholds!
      raise ConfigurationError, "fallback_options must be a Hash" unless fallback_options.is_a?(Hash)
      raise ConfigurationError, "max_retries must be a non-negative Integer" unless max_retries.is_a?(Integer) && max_retries >= 0

      %i[open_timeout read_timeout].each do |key|
        value = public_send(key)
        raise ConfigurationError, "#{key} must be a positive number" unless value.is_a?(Numeric) && value.positive?
      end
      self
    end

    def primitive
      jev_primitive.to_sym
    end

    def resolved_provider
      explicit = provider || env("IS_EVEN_AI_PROVIDER")
      return explicit.to_sym if explicit

      DETECTION_ORDER.each do |name, vars|
        return name if vars.any? { |var| env(var) }
      end
      raise ConfigurationError,
            "No provider configured. Set config.provider, IS_EVEN_AI_PROVIDER, or one of: " \
            "TYPESAFE_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, GOOGLE_API_KEY, IS_EVEN_AI_API_KEY."
    end

    def resolved_api_key(name = resolved_provider)
      api_key || API_KEY_ENV.fetch(name.to_sym, []).filter_map { |var| env(var) }.first
    end

    def resolved_base_url(name = resolved_provider)
      return base_url if base_url

      case name.to_sym
      when :jev then env("TYPESAFE_BASE_URL") || env("IS_EVEN_AI_BASE_URL")
      when :openai_compatible then env("IS_EVEN_AI_BASE_URL")
      end
    end

    # Configuration used for System 2 escalation. Credentials, model and URL of the
    # primary provider never leak into the fallback.
    def fallback_config
      copy = dup
      copy.provider = fallback_provider
      copy.api_key = nil
      copy.model = nil
      copy.base_url = nil
      copy.fallback_provider = nil
      copy.fallback_options = {}
      copy.on_uncertain = nil
      copy.strict_confidence = false
      copy.fan_out = false
      copy.merge(fallback_options)
    end

    def inspect
      pairs = DEFAULTS.keys.map do |key|
        value = key == :api_key && api_key ? "[REDACTED]" : public_send(key).inspect
        "#{key}=#{value}"
      end
      "#<#{self.class} #{pairs.join(" ")}>"
    end

    private

    def env(name)
      value = ENV.fetch(name, nil)
      value unless value.nil? || value.strip.empty?
    end

    def validate_provider!(name, label)
      return if name.nil?
      return if Providers::Registry.known?(name)

      raise ConfigurationError,
            "Unknown #{label} #{name.inspect}; expected one of #{Providers::Registry.names.join(", ")}"
    end

    def validate_thresholds!
      [yes_threshold, no_threshold].each do |value|
        raise ConfigurationError, "Thresholds must be numbers between 0.0 and 1.0" unless value.is_a?(Numeric) && value.between?(0, 1)
      end
      return if no_threshold <= yes_threshold

      raise ConfigurationError, "no_threshold (#{no_threshold}) must not exceed yes_threshold (#{yes_threshold})"
    end
  end
end
