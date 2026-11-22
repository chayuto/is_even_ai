# frozen_string_literal: true

module IsEvenAI
  module Providers
    # Anthropic Messages API, version 2026-10-21 (RESEARCH.md section 3.2): Bearer auth, no sampling
    # parameters (they return HTTP 400), GA structured output via output_config.format.
    class Anthropic < Base
      DEFAULT_BASE_URL = "https://api.anthropic.com"
      PATH = "/v1/messages"
      API_VERSION = "2026-10-21"

      def self.provider_name = :anthropic

      def default_model = "claude-haiku-5-5"

      def call(input)
        headers = { "Authorization" => "Bearer #{api_key!}", "anthropic-version" => API_VERSION }
        body = http.post_json(endpoint(DEFAULT_BASE_URL, PATH), request_body(input), headers)
        parse(input, body)
      end

      private

      # Only haiku accepts thinking: disabled. Other models think adaptively and thinking tokens
      # count toward max_tokens, so they get a larger ceiling.
      def thinking_disabled?
        model.to_s.start_with?("claude-haiku")
      end

      def request_body(input)
        body = {
          "model" => model,
          "max_tokens" => thinking_disabled? ? 256 : 1024,
          "system" => system_prompt(input),
          "messages" => [{ "role" => "user", "content" => user_prompt(input) }],
          "output_config" => { "format" => { "type" => "json_schema", "schema" => RESULT_SCHEMA } }
        }
        body["thinking"] = { "type" => "disabled" } if thinking_disabled?
        body
      end

      def parse(input, body)
        case body["stop_reason"]
        when "refusal" then raise ParseError, "anthropic refused the request"
        when "max_tokens" then raise ParseError, "anthropic response was truncated (max_tokens)"
        end

        text = Array(body["content"]).find { |block| block["type"] == "text" }&.fetch("text", nil)
        usage = body["usage"].is_a?(Hash) ? token_usage(body["usage"]["input_tokens"], body["usage"]["output_tokens"]) : nil
        generative_result(input, text: text, model: body["model"] || model, usage: usage, raw: body)
      end
    end

    Registry.register(:anthropic, Anthropic)
  end
end
