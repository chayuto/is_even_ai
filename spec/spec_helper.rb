# frozen_string_literal: true

require "webmock/rspec"
require "is_even_ai"
require "is_even_ai/cli"

WebMock.disable_net_connect!

ENV_KEYS = %w[
  IS_EVEN_AI_PROVIDER IS_EVEN_AI_API_KEY IS_EVEN_AI_BASE_URL TYPESAFE_API_KEY TYPESAFE_BASE_URL
  OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY
].freeze

module SpecHelpers
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  # Accepts a braceless hash (string keys land in **rest) as well as an explicit one.
  def json_response(body = nil, status: 200, headers: {}, **rest)
    { status: status, body: JSON.generate(body || rest), headers: JSON_HEADERS.merge(headers) }
  end

  def jev_noul_body(probability, extra_answers: {}, key: "is_even")
    {
      "model" => "jev-1.14.0",
      "answers" => { key => { "type" => "noul", "noul" => probability } }.merge(extra_answers),
      "usage" => { "input_tokens" => 100, "output_tokens" => 12 }
    }
  end

  def generative_answer(is_even:, confidence: 0.95, reasoning: "Because arithmetic.")
    JSON.generate("is_even" => is_even, "confidence" => confidence, "reasoning" => reasoning)
  end

  def openai_body(text)
    {
      "model" => "gpt-6-luna", "status" => "completed",
      "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => text }] }],
      "usage" => { "input_tokens" => 80, "output_tokens" => 20 }
    }
  end

  def anthropic_body(text)
    {
      "model" => "claude-haiku-5-5", "stop_reason" => "end_turn",
      "content" => [{ "type" => "thinking", "thinking" => "..." }, { "type" => "text", "text" => text }],
      "usage" => { "input_tokens" => 70, "output_tokens" => 18 }
    }
  end

  def gemini_body(text)
    {
      "modelVersion" => "gemini-3.5-flash-lite",
      "candidates" => [{ "finishReason" => "STOP", "content" => { "parts" => [{ "text" => text }] } }],
      "usageMetadata" => { "promptTokenCount" => 60, "candidatesTokenCount" => 15, "thoughtsTokenCount" => 5 }
    }
  end

  def stub_jev(body = nil, **response)
    body ||= response if response.keys.first.is_a?(String)
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(body ? json_response(body) : response)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!

  config.around do |example|
    saved = ENV.to_h.slice(*ENV_KEYS)
    ENV_KEYS.each { |key| ENV.delete(key) }
    previous_sleeper = IsEvenAI::HttpClient.instance_variable_get(:@sleeper)
    IsEvenAI::HttpClient.sleeper = ->(_seconds) {}
    IsEvenAI.reset_configuration!
    example.run
  ensure
    IsEvenAI.reset_configuration!
    IsEvenAI::HttpClient.sleeper = previous_sleeper
    ENV_KEYS.each { |key| ENV.delete(key) }
    saved.each { |key, value| ENV[key] = value }
  end
end
