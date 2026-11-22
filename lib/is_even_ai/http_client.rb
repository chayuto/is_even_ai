# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "uri"

module IsEvenAI
  # Minimal stdlib JSON-over-HTTPS client with retries (exponential backoff, full jitter).
  class HttpClient
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504, 529].freeze
    NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, EOFError
    ].freeze
    BILLING_MARKERS = %w[credit_balance_exhausted insufficient_quota billing_hard_limit_reached].freeze
    WRITE_TIMEOUT = 10
    BASE_DELAY = 0.5
    MAX_DELAY = 8.0
    MAX_RETRY_AFTER = 30.0

    class << self
      # Swappable so specs never actually sleep.
      attr_writer :sleeper

      def sleeper
        @sleeper ||= ->(seconds) { sleep(seconds) }
      end
    end

    def initialize(provider:, open_timeout: 5, read_timeout: 30, max_retries: 2)
      @provider = provider
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_retries = max_retries
    end

    # POSTs a JSON body and returns the parsed JSON response.
    def post_json(url, body, headers = {})
      uri = URI.parse(url)
      payload = JSON.generate(body)
      attempts = 0

      loop do
        attempts += 1
        response = perform(uri, payload, headers)
        status = response.code.to_i
        return parse_body(response) if status.between?(200, 299)

        if retryable?(status, response) && attempts <= @max_retries
          pause(retry_delay(response, attempts))
          next
        end
        raise_http_error(status, response)
      rescue *NETWORK_ERRORS => e
        raise api_error("#{@provider} request failed: #{e.class}: #{e.message}") if attempts > @max_retries

        pause(backoff(attempts))
      rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise api_error("#{@provider} connection failed: #{e.class}: #{e.message}")
      end
    end

    private

    def perform(uri, payload, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = WRITE_TIMEOUT
      http.max_retries = 0 # our retry policy is the only retry policy

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["User-Agent"] = "is_even_ai/#{VERSION}"
      headers.each { |name, value| request[name] = value }
      request.body = payload
      http.start { |connection| connection.request(request) }
    end

    def parse_body(response)
      parsed = JSON.parse(response.body.to_s)
      return parsed if parsed.is_a?(Hash)

      raise ParseError, "#{@provider} returned JSON that is not an object: #{response.body.to_s[0, 200]}"
    rescue JSON::ParserError => e
      raise ParseError, "#{@provider} returned malformed JSON (#{e.message[0, 80]}): #{response.body.to_s[0, 200]}"
    end

    def retryable?(status, response)
      return false unless RETRYABLE_STATUSES.include?(status)

      body = response.body.to_s
      BILLING_MARKERS.none? { |marker| body.include?(marker) }
    end

    def retry_delay(response, attempts)
      after = parse_retry_after(response)
      after ? [after, MAX_RETRY_AFTER].min : backoff(attempts)
    end

    def backoff(attempts)
      rand * [MAX_DELAY, BASE_DELAY * (2**(attempts - 1))].min
    end

    def pause(seconds)
      self.class.sleeper.call(seconds)
    end

    def parse_retry_after(response)
      value = response["retry-after"]
      Float(value, exception: false)&.then { |seconds| seconds.negative? ? nil : seconds }
    end

    def raise_http_error(status, response)
      body = response.body.to_s
      message = "#{@provider} API error (HTTP #{status}): #{error_message(body)}"
      details = { status_code: status, response_body: body, provider: @provider }
      raise RateLimitError.new(message, retry_after: parse_retry_after(response), **details) if status == 429

      raise APIError.new(message, **details)
    end

    def api_error(message)
      APIError.new(message, provider: @provider)
    end

    def error_message(body)
      data = JSON.parse(body)
      error = data["error"] if data.is_a?(Hash)
      text = error.is_a?(Hash) ? error["message"] : error
      (text || data.to_s).to_s[0, 300]
    rescue JSON::ParserError
      body[0, 300]
    end
  end
end
