# frozen_string_literal: true

RSpec.describe IsEvenAI::Providers::OpenAICompatible do
  def chat_body(text)
    { "model" => "llama3.2", "choices" => [{ "message" => { "role" => "assistant", "content" => text } }],
      "usage" => { "prompt_tokens" => 50, "completion_tokens" => 10 } }
  end

  context "with a local Ollama server" do
    let(:url) { "http://localhost:11434/v1/chat/completions" }

    it "works without an API key" do
      stub = stub_request(:post, url).with do |req|
        body = JSON.parse(req.body)
        !req.headers.key?("Authorization") && body["model"] == "llama3.2" && body["response_format"]["type"] == "json_schema"
      end.to_return(json_response(chat_body(generative_answer(is_even: true))))

      result = IsEvenAI.evaluate(42, provider: :openai_compatible, base_url: "http://localhost:11434/v1", model: "llama3.2")

      expect(stub).to have_been_requested
      expect(result).to have_attributes(even?: true, provider: :openai_compatible, model: "llama3.2", usage: { input_tokens: 50, output_tokens: 10 })
    end
  end

  context "with a remote gateway (OpenRouter)" do
    let(:url) { "https://openrouter.ai/api/v1/chat/completions" }
    let(:options) { { provider: :openai_compatible, base_url: "https://openrouter.ai/api/v1/", model: "typesafe/jev-router" } }

    it "sends a bearer token from IS_EVEN_AI_API_KEY" do
      ENV["IS_EVEN_AI_API_KEY"] = "or-key"
      stub = stub_request(:post, url).with(headers: { "Authorization" => "Bearer or-key" })
                                     .to_return(json_response(chat_body(generative_answer(is_even: false))))
      expect(IsEvenAI.evaluate(7, **options).even?).to be(false)
      expect(stub).to have_been_requested
    end

    it "prefers OPENAI_API_KEY" do
      ENV["IS_EVEN_AI_API_KEY"] = "generic"
      ENV["OPENAI_API_KEY"] = "openai"
      stub = stub_request(:post, url).with(headers: { "Authorization" => "Bearer openai" })
                                     .to_return(json_response(chat_body(generative_answer(is_even: true))))
      IsEvenAI.evaluate(8, **options)
      expect(stub).to have_been_requested
    end

    it "refuses to call a remote host without a key" do
      expect { IsEvenAI.evaluate(7, **options) }.to raise_error(IsEvenAI::ConfigurationError, /API key/)
    end
  end

  it "requires a base_url and a model" do
    expect { IsEvenAI.evaluate(2, provider: :openai_compatible, model: "m") }.to raise_error(IsEvenAI::ConfigurationError, /base_url/)
    expect { IsEvenAI.evaluate(2, provider: :openai_compatible, base_url: "http://localhost:1") }.to raise_error(IsEvenAI::ConfigurationError, /model/)
  end

  it "takes the base URL from IS_EVEN_AI_BASE_URL" do
    ENV["IS_EVEN_AI_BASE_URL"] = "http://127.0.0.1:8080/v1"
    stub = stub_request(:post, "http://127.0.0.1:8080/v1/chat/completions").to_return(json_response(chat_body(generative_answer(is_even: true))))
    IsEvenAI.evaluate(2, provider: :openai_compatible, model: "m")
    expect(stub).to have_been_requested
  end

  it "raises on refusals and empty choices" do
    options = { provider: :openai_compatible, base_url: "http://localhost:1", model: "m" }
    stub_request(:post, "http://localhost:1/chat/completions").to_return(json_response("choices" => [{ "message" => { "refusal" => "nope" } }]))
    expect { IsEvenAI.evaluate(2, **options) }.to raise_error(IsEvenAI::ParseError, /refused/)

    stub_request(:post, "http://localhost:1/chat/completions").to_return(json_response("choices" => []))
    expect { IsEvenAI.evaluate(2, **options) }.to raise_error(IsEvenAI::ParseError, /no choices/)
  end
end
