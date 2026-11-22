# frozen_string_literal: true

module IsEvenAI
  module Providers
    # OpenAI Responses API with strict structured output (RESEARCH.md section 3.1 / table in 5.2).
    # [UNVERIFIED] The response envelope below (output[].content[].output_text) follows the Responses
    # API reference; the research document's OpenAI section was truncated, so capture one live response.
    class OpenAI < Base
      DEFAULT_BASE_URL = "https://api.openai.com"
      PATH = "/v1/responses"

      def self.provider_name = :openai

      def default_model = "gpt-6-luna"

      def call(input)
        body = http.post_json(
          endpoint(DEFAULT_BASE_URL, PATH), request_body(input), "Authorization" => "Bearer #{api_key!}"
        )
        parse(input, body)
      end

      private

      def request_body(input)
        {
          "model" => model,
          "store" => false,
          "reasoning" => { "effort" => "none" },
          "max_output_tokens" => 256,
          "instructions" => system_prompt(input),
          "input" => user_prompt(input),
          "text" => {
            "format" => { "type" => "json_schema", "name" => "parity_check", "strict" => true, "schema" => RESULT_SCHEMA }
          }
        }
      end

      def parse(input, body)
        raise ParseError, "openai response incomplete: #{body.dig("incomplete_details", "reason")}" if body["status"] == "incomplete"

        parts = Array(body["output"]).flat_map { |item| Array(item["content"]) }
        refusal = parts.find { |part| part["type"] == "refusal" }
        raise ParseError, "openai refused the request: #{refusal["refusal"]}" if refusal

        text = parts.find { |part| part["type"] == "output_text" }&.fetch("text", nil)
        usage = body["usage"].is_a?(Hash) ? token_usage(body["usage"]["input_tokens"], body["usage"]["output_tokens"]) : nil
        generative_result(input, text: text, model: body["model"] || model, usage: usage, raw: body)
      end
    end

    Registry.register(:openai, OpenAI)
  end
end
