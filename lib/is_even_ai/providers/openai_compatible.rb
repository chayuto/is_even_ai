# frozen_string_literal: true

module IsEvenAI
  module Providers
    # Any server speaking OpenAI Chat Completions at {base_url}/chat/completions: Ollama, Groq,
    # OpenRouter (including typesafe/jev-router), LiteLLM, vLLM. base_url and model are required.
    # No token limit or sampling parameters are sent, since reasoning models reject some of them.
    class OpenAICompatible < Base
      def self.provider_name = :openai_compatible

      def call(input)
        raise ConfigurationError, "openai_compatible needs a model (config.model)" if config.model.nil?

        url = "#{base_url!.chomp("/")}/chat/completions"
        headers = {}
        key = api_key_for(url)
        headers["Authorization"] = "Bearer #{key}" if key
        parse(input, http.post_json(url, request_body(input), headers))
      end

      private

      def base_url!
        config.resolved_base_url(name) ||
          raise(ConfigurationError, "openai_compatible needs a base_url (config.base_url or IS_EVEN_AI_BASE_URL)")
      end

      # Local servers (Ollama and friends) may run without a key; remote ones may not.
      def api_key_for(url)
        key = config.resolved_api_key(name)
        return key if key
        return nil if LOCAL_HOSTS.include?(URI.parse(url).host)

        api_key!
      end

      def request_body(input)
        {
          "model" => model,
          "messages" => [
            { "role" => "system", "content" => system_prompt(input) },
            { "role" => "user", "content" => user_prompt(input) }
          ],
          "response_format" => {
            "type" => "json_schema",
            "json_schema" => { "name" => "parity_check", "strict" => true, "schema" => RESULT_SCHEMA }
          }
        }
      end

      def parse(input, body)
        choice = Array(body["choices"]).first
        raise ParseError, "#{name} returned no choices" unless choice.is_a?(Hash)

        message = choice["message"] || {}
        raise ParseError, "#{name} refused the request: #{message["refusal"]}" if message["refusal"]

        usage = body["usage"].is_a?(Hash) ? token_usage(body["usage"]["prompt_tokens"], body["usage"]["completion_tokens"]) : nil
        generative_result(input, text: message["content"], model: body["model"] || model, usage: usage, raw: body)
      end
    end

    Registry.register(:openai_compatible, OpenAICompatible)
  end
end
