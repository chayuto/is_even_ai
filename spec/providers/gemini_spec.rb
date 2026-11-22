# frozen_string_literal: true

RSpec.describe IsEvenAI::Providers::Gemini do
  let(:url) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent" }

  before { ENV["GEMINI_API_KEY"] = "gem-test" }

  it "calls generateContent with header auth and responseJsonSchema" do
    stub = stub_request(:post, url)
           .with(headers: { "x-goog-api-key" => "gem-test" }) do |req|
             body = JSON.parse(req.body)
             config = body["generationConfig"]
             config["responseMimeType"] == "application/json" && config.key?("responseJsonSchema") &&
               !config.key?("thinkingConfig") && req.uri.query.nil?
           end
           .to_return(json_response(gemini_body(generative_answer(is_even: true))))

    result = IsEvenAI.evaluate(42)

    expect(stub).to have_been_requested
    expect(result).to have_attributes(even?: true, provider: :gemini, model: "gemini-3.5-flash-lite", usage: { input_tokens: 60, output_tokens: 20 })
  end

  it "accepts GOOGLE_API_KEY" do
    ENV.delete("GEMINI_API_KEY")
    ENV["GOOGLE_API_KEY"] = "goog"
    stub = stub_request(:post, url).with(headers: { "x-goog-api-key" => "goog" })
                                   .to_return(json_response(gemini_body(generative_answer(is_even: false))))
    expect(IsEvenAI.evaluate(3).even?).to be(false)
    expect(stub).to have_been_requested
  end

  it "uses a custom model in the URL" do
    stub = stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-4-pro:generateContent")
           .to_return(json_response(gemini_body(generative_answer(is_even: true))))
    IsEvenAI.evaluate(2, model: "gemini-4-pro")
    expect(stub).to have_been_requested
  end

  it "raises on blocked prompts, safety stops and missing candidates" do
    stub_request(:post, url).to_return(json_response("promptFeedback" => { "blockReason" => "SAFETY" }))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /blocked/)

    stub_request(:post, url).to_return(json_response("candidates" => [{ "finishReason" => "SAFETY" }]))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /SAFETY/)

    stub_request(:post, url).to_return(json_response("candidates" => []))
    expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::ParseError, /no candidates/)
  end

  it "requires an API key" do
    ENV.delete("GEMINI_API_KEY")
    expect { IsEvenAI.evaluate(2, provider: :gemini) }.to raise_error(IsEvenAI::ConfigurationError, /GEMINI_API_KEY/)
  end
end
