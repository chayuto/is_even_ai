# frozen_string_literal: true

RSpec.describe IsEvenAI::Providers::OpenAI do
  let(:url) { "https://api.openai.com/v1/responses" }

  before { ENV["OPENAI_API_KEY"] = "sk-test" }

  it "calls the Responses API with strict structured output and no legacy parameters" do
    stub = stub_request(:post, url)
           .with(headers: { "Authorization" => "Bearer sk-test" }) do |req|
             body = JSON.parse(req.body)
             body["model"] == "gpt-6-luna" && body["store"] == false && body["reasoning"] == { "effort" => "none" } &&
               body["text"]["format"]["strict"] == true && !body.key?("max_tokens") && !body.key?("temperature") &&
               body["input"].include?("42")
           end
           .to_return(json_response(openai_body(generative_answer(is_even: true))))

    result = IsEvenAI.evaluate(42)

    expect(stub).to have_been_requested
    expect(result).to have_attributes(
      even?: true, uncertain?: false, provider: :openai, model: "gpt-6-luna", primitive: nil,
      probability: nil, confidence: 0.95, reasoning: "Because arithmetic.", usage: { input_tokens: 80, output_tokens: 20 }
    )
  end

  it "flags a low-confidence answer as uncertain" do
    stub_request(:post, url).to_return(json_response(openai_body(generative_answer(is_even: false, confidence: 0.2))))
    expect(IsEvenAI.evaluate("banana", allow_non_integer: true)).to have_attributes(even?: false, uncertain?: true, non_integer?: true)
  end

  it "tells the model about the type of non-integer input" do
    stub = stub_request(:post, url).with { |req| JSON.parse(req.body)["input"].include?("Ruby type: String") && JSON.parse(req.body)["instructions"].include?("baker's dozen") }
                                   .to_return(json_response(openai_body(generative_answer(is_even: false))))
    IsEvenAI.evaluate("a baker's dozen", allow_non_integer: true)
    expect(stub).to have_been_requested
  end

  it "uses the model override and base_url proxy" do
    stub = stub_request(:post, "http://proxy.test/v1/responses")
           .with { |req| JSON.parse(req.body)["model"] == "gpt-6.1-sol" }
           .to_return(json_response(openai_body(generative_answer(is_even: true))))
    IsEvenAI.evaluate(2, model: "gpt-6.1-sol", base_url: "http://proxy.test")
    expect(stub).to have_been_requested
  end

  it "raises on refusals, incomplete responses and bad payloads" do
    refusal = { "output" => [{ "content" => [{ "type" => "refusal", "refusal" => "no" }] }] }
    stub_request(:post, url).to_return(json_response(refusal))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /refused/)

    stub_request(:post, url).to_return(json_response("status" => "incomplete", "incomplete_details" => { "reason" => "max_output_tokens" }))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /incomplete/)

    stub_request(:post, url).to_return(json_response(openai_body("not json at all")))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /non-JSON/)

    stub_request(:post, url).to_return(json_response(openai_body(JSON.generate("is_even" => "yes"))))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /boolean/)

    stub_request(:post, url).to_return(json_response("output" => []))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /no text/)
  end

  it "tolerates JSON wrapped in prose or code fences" do
    wrapped = "Here you go:\n```json\n#{generative_answer(is_even: true)}\n```"
    stub_request(:post, url).to_return(json_response(openai_body(wrapped)))
    expect(IsEvenAI.evaluate(2).even?).to be(true)
  end

  it "requires an API key" do
    ENV.delete("OPENAI_API_KEY")
    expect { IsEvenAI.evaluate(2, provider: :openai) }.to raise_error(IsEvenAI::ConfigurationError, /OPENAI_API_KEY/)
  end

  it "surfaces API errors" do
    stub_request(:post, url).to_return(status: 400, body: JSON.generate("error" => { "message" => "max_tokens not supported" }))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::APIError, /max_tokens not supported/)
  end
end
