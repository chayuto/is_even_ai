# frozen_string_literal: true

RSpec.describe IsEvenAI::Providers::Jev do
  let(:url) { "https://api.typesafe.ai/v1/systemone" }

  before { ENV["TYPESAFE_API_KEY"] = "jev-key" }

  def sent_body
    JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
  end

  describe "noul (default)" do
    it "sends the documented request and maps a confident yes" do
      stub = stub_request(:post, url)
             .with(headers: { "Authorization" => "Bearer jev-key", "Content-Type" => "application/json" })
             .to_return(json_response(jev_noul_body(0.99)))

      result = IsEvenAI.evaluate(42)

      expect(stub).to have_been_requested
      expect(sent_body).to eq(
        "model" => "jev-latest",
        "state" => { "value" => 42 },
        "questions" => { "is_even" => { "type" => "noul", "instructions" => "Is `value` an even integer (divisible by 2 with no remainder)?" } }
      )
      expect(result).to have_attributes(
        even?: true, odd?: false, uncertain?: false, non_integer?: false, probability: 0.99,
        provider: :jev, model: "jev-1.14.0", primitive: :noul, escalated?: false, fan_out: nil
      )
      expect(result.confidence).to be_within(1e-9).of(0.98)
      expect(result.usage).to eq(input_tokens: 100, output_tokens: 12)
      expect(result.latency_ms).to be >= 0
      expect(result.raw["model"]).to eq("jev-1.14.0")
    end

    it "serializes huge integers without float precision loss" do
      stub_jev(jev_noul_body(0.99))
      IsEvenAI.evaluate(2**100)
      expect(sent_body["state"]["value"]).to eq(2**100)
    end

    {
      0.7 => [true, false], 0.71 => [true, false], 0.3 => [false, false], 0.01 => [false, false],
      0.5 => [true, true], 0.69 => [true, true], 0.31 => [false, true], 0.49 => [false, true]
    }.each do |probability, (even, uncertain)|
      it "maps probability #{probability} to even=#{even} uncertain=#{uncertain}" do
        stub_jev(jev_noul_body(probability))
        result = IsEvenAI.evaluate(10)
        expect(result.even?).to be(even)
        expect(result.uncertain?).to be(uncertain)
      end
    end

    it "honours custom thresholds" do
      stub_jev(jev_noul_body(0.8))
      result = IsEvenAI.evaluate(10, yes_threshold: 0.9, no_threshold: 0.1)
      expect(result).to have_attributes(uncertain?: true, even?: true)
    end

    it "raises UncertainParityError carrying the result in strict mode" do
      stub_jev(jev_noul_body(0.5))
      expect { IsEvenAI.even?(10, strict_confidence: true) }.to raise_error(IsEvenAI::UncertainParityError) { |e|
        expect(e.result).to be_a(IsEvenAI::Result)
        expect(e.result.probability).to eq(0.5)
      }
    end

    it "raises ParseError when the answer is missing or malformed" do
      stub_jev("model" => "jev-1.14.0", "answers" => {})
      expect { IsEvenAI.evaluate(1) }.to raise_error(IsEvenAI::ParseError, /missing/)

      stub_jev("model" => "jev-1.14.0", "answers" => { "is_even" => { "type" => "noul", "noul" => "yes" } })
      expect { IsEvenAI.evaluate(1) }.to raise_error(IsEvenAI::ParseError, /not a number/)

      stub_jev("nope" => true)
      expect { IsEvenAI.evaluate(1) }.to raise_error(IsEvenAI::ParseError, /no answers/)
    end
  end

  describe "choice" do
    let(:choice_answer) do
      { "type" => "choice", "choice" => "even", "confidence" => 0.985,
        "probabilities" => { "even" => 0.99, "odd" => 0.01 } }
    end

    it "sends even/odd criteria and maps probabilities" do
      stub_jev("model" => "jev-1.14.0", "answers" => { "parity" => choice_answer }, "usage" => { "input_tokens" => 1, "output_tokens" => 2 })
      result = IsEvenAI.evaluate(42, primitive: :choice)

      expect(sent_body["questions"]["parity"]["criteria"].keys).to eq(%w[even odd])
      expect(result).to have_attributes(even?: true, uncertain?: false, probability: 0.99, confidence: 0.985, primitive: :choice)
    end

    it "adds a not_an_integer option only when the override is enabled" do
      answer = { "type" => "choice", "choice" => "not_an_integer", "confidence" => 0.9,
                 "probabilities" => { "even" => 0.02, "odd" => 0.03, "not_an_integer" => 0.95 } }
      stub_jev("model" => "jev-1.14.0", "answers" => { "parity" => answer })

      result = IsEvenAI.evaluate("banana", primitive: :choice, allow_non_integer: true)

      expect(sent_body["questions"]["parity"]["criteria"].keys).to eq(%w[even odd not_an_integer])
      expect(result).to have_attributes(even?: false, uncertain?: true, non_integer?: true)
      expect { IsEvenAI.evaluate("banana", primitive: :choice, allow_non_integer: true, strict_confidence: true) }
        .to raise_error(IsEvenAI::UncertainParityError)
    end

    it "applies the threshold band to the even probability" do
      choice_answer["probabilities"] = { "even" => 0.55, "odd" => 0.45 }
      stub_jev("model" => "jev-1.14.0", "answers" => { "parity" => choice_answer })
      expect(IsEvenAI.evaluate(3, primitive: :choice)).to have_attributes(uncertain?: true, even?: true)
    end

    it "rejects a malformed choice answer" do
      stub_jev("model" => "jev-1.14.0", "answers" => { "parity" => { "type" => "choice" } })
      expect { IsEvenAI.evaluate(3, primitive: :choice) }.to raise_error(IsEvenAI::ParseError, /choice/)
    end
  end

  describe "score" do
    def score_body(score, confidence: 0.97)
      { "model" => "jev-1.14.0", "answers" => { "evenness" => { "type" => "score", "score" => score, "confidence" => confidence } } }
    end

    it "sends the five-level comedy rubric" do
      stub_jev(score_body(3.9))
      IsEvenAI.evaluate(42, primitive: :score)
      expect(sent_body["questions"]["evenness"]["criteria"]).to eq(described_class::SCORE_RUBRIC)
      expect(described_class::SCORE_RUBRIC.size).to eq(5)
    end

    it "normalizes the score and carries the rubric label as reasoning" do
      stub_jev(score_body(3.9))
      result = IsEvenAI.evaluate(42, primitive: :score)
      expect(result).to have_attributes(even?: true, uncertain?: false, confidence: 0.97, primitive: :score)
      expect(result.probability).to be_within(1e-9).of(0.975)
      expect(result.reasoning).to start_with("Unquestionably even")
    end

    it "treats the middle of the rubric as uncertain" do
      stub_jev(score_body(2.0))
      expect(IsEvenAI.evaluate(7, primitive: :score)).to have_attributes(uncertain?: true, even?: true)
    end

    it "treats low scores as odd" do
      stub_jev(score_body(0.2))
      result = IsEvenAI.evaluate(7, primitive: :score)
      expect(result).to have_attributes(even?: false, uncertain?: false)
      expect(result.reasoning).to start_with("Aggressively odd")
    end
  end

  describe "fan_out" do
    let(:extras) do
      {
        "is_odd" => { "type" => "noul", "noul" => 0.01 },
        "is_suspiciously_large" => { "type" => "noul", "noul" => 0.02 }
      }
    end

    it "asks the extra questions in the same request" do
      stub = stub_jev(jev_noul_body(0.99, extra_answers: extras))
      result = IsEvenAI.evaluate(42, fan_out: true)

      expect(stub).to have_been_requested.once
      expect(sent_body["questions"].keys).to eq(%w[is_even is_odd is_suspiciously_large])
      expect(result.fan_out).to eq(is_odd: 0.01, is_suspiciously_large: 0.02)
    end

    it "adds represents_integer when the non-integer override is on" do
      extras["represents_integer"] = { "type" => "noul", "noul" => 0.98 }
      stub_jev(jev_noul_body(0.95, extra_answers: extras))
      result = IsEvenAI.evaluate("forty-two", fan_out: true, allow_non_integer: true)

      expect(sent_body["questions"].keys).to include("represents_integer")
      expect(result.fan_out[:represents_integer]).to eq(0.98)
    end

    it "records nil for fan-out answers the server did not return in the expected shape" do
      stub_jev(jev_noul_body(0.9, extra_answers: { "is_odd" => { "type" => "noul" } }))
      expect(IsEvenAI.evaluate(4, fan_out: true).fan_out).to eq(is_odd: nil)
    end
  end

  describe "non-integer override" do
    it "sends type metadata in the state and semantic criteria" do
      stub_jev(jev_noul_body(0.96))
      result = IsEvenAI.evaluate("forty-two", allow_non_integer: true)

      expect(sent_body["state"]).to eq("value" => "forty-two", "ruby_type" => "String", "non_integer_override" => true)
      expect(sent_body["questions"]["is_even"]["criteria"].keys).to eq(%w[true false])
      expect(result).to have_attributes(even?: true, non_integer?: true)
    end

    it "stringifies values JSON cannot carry" do
      stub_jev(jev_noul_body(0.02))
      [Float::INFINITY, Float::NAN, Rational(9, 2), :banana, [1, 2]].each do |value|
        IsEvenAI.evaluate(value, allow_non_integer: true)
        state = sent_body["state"]
        expect(state["ruby_type"]).to eq(value.class.name)
        expect(state["value"]).to be_a(String)
      end
    end

    it "keeps finite floats numeric" do
      stub_jev(jev_noul_body(0.9))
      IsEvenAI.evaluate(4.0, allow_non_integer: true)
      expect(sent_body["state"]).to eq("value" => 4.0, "ruby_type" => "Float", "non_integer_override" => true)
    end

    it "keeps plain integers free of override metadata even when the override is on" do
      stub_jev(jev_noul_body(0.9))
      IsEvenAI.evaluate(4, allow_non_integer: true)
      expect(sent_body["state"]).to eq("value" => 4)
    end
  end

  describe "base_url and credentials" do
    it "targets a custom base_url (LiteLLM, Semlf, ...)" do
      stub = stub_request(:post, "http://localhost:4000/v1/systemone").to_return(json_response(jev_noul_body(0.9)))
      IsEvenAI.evaluate(2, base_url: "http://localhost:4000")
      expect(stub).to have_been_requested
    end

    it "does not double a trailing /v1" do
      stub = stub_request(:post, "http://proxy.test/v1/systemone").to_return(json_response(jev_noul_body(0.9)))
      IsEvenAI.evaluate(2, base_url: "http://proxy.test/v1/")
      expect(stub).to have_been_requested
    end

    it "reads TYPESAFE_BASE_URL" do
      ENV["TYPESAFE_BASE_URL"] = "https://jev.internal"
      stub = stub_request(:post, "https://jev.internal/v1/systemone").to_return(json_response(jev_noul_body(0.9)))
      IsEvenAI.evaluate(2)
      expect(stub).to have_been_requested
    end

    it "raises ConfigurationError without an API key" do
      ENV.delete("TYPESAFE_API_KEY")
      expect { IsEvenAI.evaluate(2, provider: :jev) }.to raise_error(IsEvenAI::ConfigurationError, /TYPESAFE_API_KEY/)
    end

    it "honours a requested model" do
      stub_jev(jev_noul_body(0.9))
      IsEvenAI.evaluate(2, model: "jev-1.13.0")
      expect(sent_body["model"]).to eq("jev-1.13.0")
    end
  end

  describe "errors" do
    it "raises APIError on 401" do
      stub_jev(status: 401, body: JSON.generate("error" => { "message" => "bad token" }))
      expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::APIError, /bad token/)
    end

    it "raises RateLimitError on persistent 429" do
      stub_jev(status: 429, body: "{}", headers: { "Retry-After" => "1" })
      expect { IsEvenAI.evaluate(2) }.to raise_error(IsEvenAI::RateLimitError)
    end
  end
end
