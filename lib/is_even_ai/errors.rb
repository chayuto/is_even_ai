# frozen_string_literal: true

module IsEvenAI
  class Error < StandardError; end

  # Missing API key, unknown provider, invalid primitive or thresholds.
  class ConfigurationError < Error; end

  # A non-Integer was passed while allow_non_integer is false, or nil was passed at all.
  class InvalidInputError < Error; end

  class APIError < Error
    attr_reader :status_code, :response_body, :provider

    def initialize(message = nil, status_code: nil, response_body: nil, provider: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
      @provider = provider
    end
  end

  class RateLimitError < APIError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **details)
      super(message, **details)
      @retry_after = retry_after
    end
  end

  # Malformed or unexpected provider payload.
  class ParseError < Error; end

  # Parity could not be established with enough certainty.
  class UncertainParityError < Error
    attr_reader :result

    def initialize(message = "Parity is uncertain", result: nil)
      super(message)
      @result = result
    end
  end
end
