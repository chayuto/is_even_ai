# frozen_string_literal: true

module IsEvenAI
  module Providers
    # Shared contract for providers. Subclasses implement #call(input) -> Result and
    # #default_model; generative providers reuse the prompt and parsing helpers below.
    class Base
      LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1] 0.0.0.0 host.docker.internal].freeze

      RESULT_SCHEMA = {
        "type" => "object",
        "properties" => {
          "is_even" => { "type" => "boolean" },
          "confidence" => { "type" => "number" },
          "reasoning" => { "type" => "string" }
        },
        "required" => %w[is_even confidence reasoning],
        "additionalProperties" => false
      }.freeze

      SYSTEM_PROMPT = <<~PROMPT
        You are a rigorous parity-checking service. Determine whether the supplied value is an even integer (an integer divisible by 2 with no remainder).
        Respond only with JSON matching the schema: is_even (boolean), confidence (number from 0 to 1 describing how certain you are), reasoning (one short sentence).
      PROMPT

      NON_INTEGER_PROMPT = <<~PROMPT
        The value may not be an integer. Evaluate whether it semantically represents an even integer: for example "42", "forty-two", 4.0 and "a dozen" do; "a baker's dozen" (13), 4.5, "banana" and infinity do not.
        When the value does not represent an even integer, set is_even to false, lower your confidence for values that are not integers at all, and explain why.
      PROMPT

      attr_reader :config

      def self.provider_name
        raise NotImplementedError, "#{name} must define .provider_name"
      end

      def initialize(config)
        @config = config
      end

      def call(_input)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      def default_model
        nil
      end

      def model
        config.model || default_model
      end

      def name
        self.class.provider_name
      end

      private

      def http
        @http ||= HttpClient.new(
          provider: name, open_timeout: config.open_timeout,
          read_timeout: config.read_timeout, max_retries: config.max_retries
        )
      end

      def api_key!
        key = config.resolved_api_key(name)
        return key if key

        env_vars = Configuration::API_KEY_ENV.fetch(name, []).join(" or ")
        hint = env_vars.empty? ? "config.api_key" : "#{env_vars} or config.api_key"
        raise ConfigurationError, "Missing API key for provider :#{name}. Set #{hint}."
      end

      # Joins the configured (or default) base URL and an API path, tolerating a trailing "/v1".
      def endpoint(default_base, path)
        base = (config.resolved_base_url(name) || default_base).to_s.chomp("/")
        return base if base.end_with?(path)

        base = base.delete_suffix("/v1") if path.start_with?("/v1/")
        "#{base}#{path}"
      end

      def non_integer?(input)
        !input.is_a?(Integer)
      end

      # JSON-safe representation of the input value.
      def serialize_value(input)
        case input
        when Integer, String then input
        when Float then input.finite? ? input : input.to_s
        when Numeric, Symbol then input.to_s
        else input.inspect
        end
      end

      def system_prompt(input)
        non_integer?(input) ? "#{SYSTEM_PROMPT}#{NON_INTEGER_PROMPT}" : SYSTEM_PROMPT
      end

      def user_prompt(input)
        "Value: #{serialize_value(input).inspect}\nRuby type: #{input.class.name}"
      end

      # Maps a calibrated probability onto [even, uncertain] using the configured bands.
      def decide(probability)
        if probability >= config.yes_threshold
          [true, false]
        elsif probability <= config.no_threshold
          [false, false]
        else
          [probability >= 0.5, true]
        end
      end

      def parse_json_text(text)
        raise ParseError, "#{name} returned no text content" if text.nil? || text.strip.empty?

        JSON.parse(text)
      rescue JSON::ParserError
        embedded = text[/\{.*\}/m]
        begin
          embedded ? JSON.parse(embedded) : raise(ParseError, "#{name} returned non-JSON text: #{text[0, 200]}")
        rescue JSON::ParserError
          raise ParseError, "#{name} returned non-JSON text: #{text[0, 200]}"
        end
      end

      # Builds a Result from the structured {is_even, confidence, reasoning} answer of a generative model.
      def generative_result(input, text:, model:, usage:, raw:)
        data = parse_json_text(text)
        raise ParseError, "#{name} answer is missing a boolean is_even: #{text[0, 200]}" unless data.is_a?(Hash) && [true, false].include?(data["is_even"])

        confidence = data["confidence"].is_a?(Numeric) ? data["confidence"].to_f.clamp(0.0, 1.0) : nil
        Result.new(
          input: input, even: data["is_even"], provider: name, model: model, non_integer: non_integer?(input),
          uncertain: !confidence.nil? && confidence <= config.no_threshold,
          confidence: confidence, reasoning: data["reasoning"], usage: usage, raw: raw
        )
      end

      def token_usage(input_tokens, output_tokens)
        return nil if input_tokens.nil? && output_tokens.nil?

        { input_tokens: input_tokens, output_tokens: output_tokens }
      end
    end
  end
end
