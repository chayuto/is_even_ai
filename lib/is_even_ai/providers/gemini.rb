# frozen_string_literal: true

module IsEvenAI
  module Providers
    # Google Gemini via the legacy generateContent endpoint (RESEARCH.md section 3.3). The newer
    # Interactions API is not used: its raw response shape is [UNVERIFIED] in the research.
    class Gemini < Base
      DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"
      BLOCKING_FINISH_REASONS = %w[SAFETY PROHIBITED_CONTENT BLOCKLIST SPII RECITATION MAX_TOKENS].freeze

      def self.provider_name = :gemini

      def default_model = "gemini-3.5-flash-lite"

      def call(input)
        url = endpoint(DEFAULT_BASE_URL, "/v1beta/models/#{model}:generateContent")
        body = http.post_json(url, request_body(input), "x-goog-api-key" => api_key!)
        parse(input, body)
      end

      private

      def request_body(input)
        {
          "systemInstruction" => { "parts" => [{ "text" => system_prompt(input) }] },
          "contents" => [{ "role" => "user", "parts" => [{ "text" => user_prompt(input) }] }],
          "generationConfig" => {
            "responseMimeType" => "application/json",
            "responseJsonSchema" => RESULT_SCHEMA,
            "maxOutputTokens" => 1024
          }
        }
      end

      def parse(input, body)
        block_reason = body.dig("promptFeedback", "blockReason")
        raise ParseError, "gemini blocked the prompt: #{block_reason}" if block_reason

        candidate = Array(body["candidates"]).first
        raise ParseError, "gemini returned no candidates" unless candidate.is_a?(Hash)

        finish = candidate["finishReason"]
        raise ParseError, "gemini stopped with finishReason #{finish}" if BLOCKING_FINISH_REASONS.include?(finish)

        text = Array(candidate.dig("content", "parts")).find { |part| part["text"] }&.fetch("text", nil)
        generative_result(input, text: text, model: body["modelVersion"] || model, usage: usage(body["usageMetadata"]), raw: body)
      end

      def usage(metadata)
        return nil unless metadata.is_a?(Hash)

        output = metadata["candidatesTokenCount"].to_i + metadata["thoughtsTokenCount"].to_i
        token_usage(metadata["promptTokenCount"], output)
      end
    end

    Registry.register(:gemini, Gemini)
  end
end
