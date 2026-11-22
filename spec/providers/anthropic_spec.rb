# frozen_string_literal: true

RSpec.describe IsEvenAI::Providers::Anthropic do
  let(:url) { "https://api.anthropic.com/v1/messages" }

  before { ENV["ANTHROPIC_API_KEY"] = "ant-test" }

  it "sends 2026-10-21 headers, structured output and no sampling parameters" do
    stub = stub_request(:post, url)
           .with(headers: { "Authorization" => "Bearer ant-test", "anthropic-version" => "2026-10-21" }) do |req|
             body = JSON.parse(req.body)
             body["model"] == "claude-haiku-5-5" && body["thinking"] == { "type" => "disabled" } &&
               body["output_config"]["format"]["type"] == "json_schema" &&
               %w[temperature top_p top_k].none? { |k| body.key?(k) } && body["max_tokens"] == 256
           end
           .to_return(json_response(anthropic_body(generative_answer(is_even: true))))

    result = IsEvenAI.evaluate(42)

    expect(stub).to have_been_requested
    expect(result).to have_attributes(even?: true, provider: :anthropic, model: "claude-haiku-5-5", usage: { input_tokens: 70, output_tokens: 18 })
  end

  it "skips the text-block lookup trap: picks the text block after thinking blocks" do
    stub_request(:post, url).to_return(json_response(anthropic_body(generative_answer(is_even: false))))
    expect(IsEvenAI.evaluate(3).even?).to be(false)
  end

  it "does not disable thinking on other models and raises max_tokens" do
    stub = stub_request(:post, url).with do |req|
      body = JSON.parse(req.body)
      !body.key?("thinking") && body["max_tokens"] == 1024 && body["model"] == "claude-sonnet-5-5"
    end.to_return(json_response(anthropic_body(generative_answer(is_even: true))))
    IsEvenAI.evaluate(2, model: "claude-sonnet-5-5")
    expect(stub).to have_been_requested
  end

  it "traps refusals and truncation" do
    stub_request(:post, url).to_return(json_response("stop_reason" => "refusal", "content" => []))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /refused/)

    stub_request(:post, url).to_return(json_response("stop_reason" => "max_tokens", "content" => []))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /truncated/)

    stub_request(:post, url).to_return(json_response("stop_reason" => "end_turn", "content" => [{ "type" => "thinking" }]))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /no text/)
  end

  it "retries overloaded (529) responses" do
    stub_request(:post, url).to_return({ status: 529, body: "{}" }, json_response(anthropic_body(generative_answer(is_even: true))))
    expect(IsEvenAI.evaluate(2).even?).to be(true)
  end

  it "requires an API key" do
    ENV.delete("ANTHROPIC_API_KEY")
    expect { IsEvenAI.evaluate(2, provider: :anthropic) }.to raise_error(IsEvenAI::ConfigurationError, /ANTHROPIC_API_KEY/)
  end
end
