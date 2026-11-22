# frozen_string_literal: true

require "json"
require "benchmark"

require_relative "is_even_ai/version"
require_relative "is_even_ai/errors"
require_relative "is_even_ai/result"
require_relative "is_even_ai/cache"
require_relative "is_even_ai/http_client"
require_relative "is_even_ai/providers/registry"
require_relative "is_even_ai/configuration"
require_relative "is_even_ai/providers/base"
require_relative "is_even_ai/providers/jev"
require_relative "is_even_ai/providers/openai"
require_relative "is_even_ai/providers/anthropic"
require_relative "is_even_ai/providers/gemini"
require_relative "is_even_ai/providers/openai_compatible"
require_relative "is_even_ai/refinements"

# Determines integer parity with a calibrated System One decision model or a frontier LLM,
# because modulo arithmetic is from the 1970s.
module IsEvenAI
  CONFIG_MUTEX = Mutex.new
  private_constant :CONFIG_MUTEX

  class << self
    def configuration
      CONFIG_MUTEX.synchronize { @configuration ||= Configuration.new }
    end

    def configure
      yield configuration
      configuration
    end

    def reset_configuration!
      CONFIG_MUTEX.synchronize { @configuration = Configuration.new }
      clear_cache!
      nil
    end

    def clear_cache!
      default_cache.clear
    end

    def even?(input, **)
      evaluate(input, **).even?
    end

    def odd?(input, **)
      evaluate(input, **).odd?
    end

    # Full decision telemetry. Accepts any configuration option as a per-call keyword.
    def evaluate(input, **options)
      config = configuration.merge(options)
      validate_input!(input, config)

      provider = Providers::Registry.build(config)
      store = Cache.resolve(config.cache, default: default_cache)
      key = cache_key(input, config, provider) if store
      cached = store&.read(key)
      return cached if cached

      result = resolve_uncertainty(execute(provider, input), input, config)
      store&.write(key, result)
      result
    end

    private

    def default_cache
      CONFIG_MUTEX.synchronize { @default_cache ||= Cache.new }
    end

    def execute(provider, input)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = provider.call(input)
      result.with(latency_ms: elapsed_ms(started))
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0).round(3)
    end

    def validate_input!(input, config)
      return if input.is_a?(Integer)

      if input.nil?
        raise InvalidInputError, "nil is not a number, and not even the AI can judge its parity. " \
                                 "Pass a value (or stringify it deliberately, e.g. \"nil\", with allow_non_integer: true)."
      end
      return if config.allow_non_integer

      raise InvalidInputError, "Expected an Integer but got #{input.class} (#{input.inspect}). " \
                               "Pass allow_non_integer: true (or set config.allow_non_integer = true) " \
                               "to let the AI judge non-integers anyway."
    end

    # System 1 -> System 2: escalate, ask a human, or refuse to guess.
    def resolve_uncertainty(result, input, config)
      return result unless result.uncertain?

      if config.fallback_provider
        escalated = escalate(result, input, config)
        return escalated unless escalated.uncertain? && config.strict_confidence

        raise UncertainParityError.new(
          "Parity of #{input.inspect} is uncertain even after escalating to #{config.fallback_provider}", result: escalated
        )
      end

      if config.on_uncertain
        resolved = config.on_uncertain.call(result)
        return resolved if resolved.is_a?(Result)
      end

      return result unless config.strict_confidence

      raise UncertainParityError.new(
        "Parity of #{input.inspect} is uncertain (probability #{result.probability.inspect}, " \
        "confidence #{result.confidence.inspect}) and no fallback_provider or on_uncertain hook resolved it",
        result: result
      )
    end

    def escalate(original, input, config)
      fallback = config.fallback_config
      fallback.validate!
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Providers::Registry.build(fallback).call(input)
      result.with(
        escalated: true,
        latency_ms: original.latency_ms + elapsed_ms(started),
        raw: result.raw.merge(escalated_from: original.to_h)
      )
    end

    def cache_key(input, config, provider)
      JSON.generate(
        [
          provider.name, provider.model, config.resolved_base_url(provider.name), config.primitive,
          input.class.name, input.to_s, config.allow_non_integer, config.fan_out,
          config.yes_threshold, config.no_threshold, config.strict_confidence,
          config.fallback_provider, config.fallback_options.to_a.map(&:to_s)
        ]
      )
    end
  end
end
