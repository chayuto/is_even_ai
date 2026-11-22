# frozen_string_literal: true

RSpec.describe IsEvenAI do
  before { ENV["TYPESAFE_API_KEY"] = "jev-key" }

  describe "configuration" do
    it "yields and persists configuration" do
      described_class.configure { |c| c.yes_threshold = 0.9 }
      expect(described_class.configuration.yes_threshold).to eq(0.9)
    end

    it "resets" do
      described_class.configure { |c| c.yes_threshold = 0.9 }
      described_class.reset_configuration!
      expect(described_class.configuration.yes_threshold).to eq(0.7)
    end

    it "applies global configuration to calls" do
      described_class.configure { |c| c.base_url = "http://global.test" }
      stub = stub_request(:post, "http://global.test/v1/systemone").to_return(json_response(jev_noul_body(0.9)))
      described_class.even?(2)
      expect(stub).to have_been_requested
    end

    it "lets per-call keywords override global configuration" do
      described_class.configure { |c| c.provider = :openai }
      stub_jev(jev_noul_body(0.9))
      expect(described_class.evaluate(2, provider: :jev).provider).to eq(:jev)
    end

    it "rejects unknown per-call options" do
      expect { described_class.even?(2, flavour: :mint) }.to raise_error(IsEvenAI::ConfigurationError)
    end

    it "fails clearly when nothing is configured" do
      ENV.delete("TYPESAFE_API_KEY")
      expect { described_class.even?(2) }.to raise_error(IsEvenAI::ConfigurationError, /No provider configured/)
    end
  end

  describe "predicates" do
    it "returns booleans" do
      stub_jev(jev_noul_body(0.99))
      expect(described_class.even?(42)).to be(true)
      expect(described_class.odd?(42)).to be(false)
    end

    it "accepts per-call options" do
      stub_jev("model" => "jev-1.14.0", "answers" => { "parity" => { "type" => "choice", "choice" => "odd", "confidence" => 0.9, "probabilities" => { "even" => 0.05, "odd" => 0.95 } } })
      expect(described_class.odd?(41, provider: :jev, primitive: :choice)).to be(true)
    end
  end

  describe "#evaluate" do
    it "returns a serializable Result" do
      stub_jev(jev_noul_body(0.99))
      result = described_class.evaluate(42)
      hash = result.to_h

      expect(hash).to include(input: 42, even: true, odd: false, provider: :jev, primitive: :noul)
      expect(JSON.parse(JSON.generate(hash))["model"]).to eq("jev-1.14.0")
      expect(result).to be_frozen
    end

    it "serializes non-integer input safely" do
      stub_jev(jev_noul_body(0.01))
      hash = described_class.evaluate(Float::NAN, allow_non_integer: true).to_h
      expect(hash[:input]).to eq("NaN")
      expect(described_class.evaluate(Rational(1, 2), allow_non_integer: true).to_h[:input]).to eq("1/2")
    end
  end

  describe "input validation" do
    ["42", "forty-two", 4.0, 4.5, Float::INFINITY, {}, [], :four, Object.new].each do |value|
      it "rejects #{value.inspect[0, 20]} by default with a hint" do
        expect { described_class.even?(value) }.to raise_error(IsEvenAI::InvalidInputError, /allow_non_integer: true.*config\.allow_non_integer = true/m)
      end
    end

    it "rejects nil" do
      expect { described_class.even?(nil) }.to raise_error(IsEvenAI::InvalidInputError, /nil/)
    end

    it "rejects nil even with the override" do
      expect { described_class.even?(nil, allow_non_integer: true) }.to raise_error(IsEvenAI::InvalidInputError, /nil/)
    end

    it "makes no network call for rejected input" do
      expect { described_class.even?("42") }.to raise_error(IsEvenAI::InvalidInputError)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it "accepts every non-nil object with the per-call override" do
      stub_jev(jev_noul_body(0.9))
      ["42", "forty-two", "a baker's dozen", 4.0, 4.5, Float::INFINITY, Float::NAN, 2r, :banana, [2], {}].each do |value|
        result = described_class.evaluate(value, allow_non_integer: true)
        expect(result.non_integer?).to be(true)
      end
    end

    it "accepts non-integers with the global override" do
      described_class.configure { |c| c.allow_non_integer = true }
      stub_jev(jev_noul_body(0.9))
      expect(described_class.evaluate("42").non_integer?).to be(true)
    end

    it "records non_integer false for plain integers" do
      stub_jev(jev_noul_body(0.9))
      expect(described_class.evaluate(-3, allow_non_integer: true).non_integer?).to be(false)
    end
  end

  describe "System 1 -> System 2 escalation" do
    let(:claude_url) { "https://api.anthropic.com/v1/messages" }

    before do
      ENV["ANTHROPIC_API_KEY"] = "ant"
      stub_jev(jev_noul_body(0.5))
    end

    it "escalates uncertain results to the fallback provider" do
      claude = stub_request(:post, claude_url).to_return(json_response(anthropic_body(generative_answer(is_even: false))))

      result = described_class.evaluate(7, fallback_provider: :anthropic)

      expect(claude).to have_been_requested
      expect(result).to have_attributes(escalated?: true, provider: :anthropic, even?: false)
      expect(result.raw[:escalated_from]).to include(provider: :jev, probability: 0.5, uncertain: true)
      expect(result.raw["stop_reason"]).to eq("end_turn")
    end

    it "does not touch the fallback for confident results" do
      stub_jev(jev_noul_body(0.99))
      claude = stub_request(:post, claude_url)
      result = described_class.evaluate(8, fallback_provider: :anthropic)
      expect(claude).not_to have_been_requested
      expect(result.escalated?).to be(false)
    end

    it "passes fallback_options to the fallback provider" do
      claude = stub_request(:post, claude_url).with { |r| JSON.parse(r.body)["model"] == "claude-opus-5-5" && r.headers["Authorization"] == "Bearer other-key" }
                                              .to_return(json_response(anthropic_body(generative_answer(is_even: true))))
      described_class.evaluate(8, fallback_provider: :anthropic, fallback_options: { model: "claude-opus-5-5", api_key: "other-key" })
      expect(claude).to have_been_requested
    end

    it "does not leak the Jev key to the fallback" do
      ENV.delete("ANTHROPIC_API_KEY")
      expect { described_class.evaluate(7, api_key: "jev-only", fallback_provider: :anthropic) }
        .to raise_error(IsEvenAI::ConfigurationError, /ANTHROPIC_API_KEY/)
    end

    it "raises when strict and even the fallback is not confident" do
      stub_request(:post, claude_url).to_return(json_response(anthropic_body(generative_answer(is_even: true, confidence: 0.1))))
      expect { described_class.evaluate(7, fallback_provider: :anthropic, strict_confidence: true) }
        .to raise_error(IsEvenAI::UncertainParityError) { |e| expect(e.result).to have_attributes(escalated?: true, provider: :anthropic) }
    end

    it "does not raise for an unconfident fallback when not strict" do
      stub_request(:post, claude_url).to_return(json_response(anthropic_body(generative_answer(is_even: true, confidence: 0.1))))
      expect(described_class.evaluate(7, fallback_provider: :anthropic)).to have_attributes(escalated?: true, uncertain?: true)
    end

    it "propagates fallback API failures" do
      stub_request(:post, claude_url).to_return(status: 401, body: "{}")
      expect { described_class.evaluate(7, fallback_provider: :anthropic) }.to raise_error(IsEvenAI::APIError)
    end

    it "calls on_uncertain and returns the Result it resolves" do
      seen = nil
      human = lambda do |result|
        seen = result
        result.with(even: true, uncertain: false, reasoning: "A human checked.")
      end

      result = described_class.evaluate(7, on_uncertain: human, strict_confidence: true)

      expect(seen).to be_a(IsEvenAI::Result)
      expect(result).to have_attributes(even?: true, uncertain?: false, reasoning: "A human checked.")
    end

    it "prefers fallback_provider over on_uncertain" do
      stub_request(:post, claude_url).to_return(json_response(anthropic_body(generative_answer(is_even: true))))
      hook = ->(_result) { raise "should not run" }
      expect(described_class.evaluate(7, fallback_provider: :anthropic, on_uncertain: hook).escalated?).to be(true)
    end

    it "raises when on_uncertain does not resolve and strict_confidence is on" do
      expect { described_class.evaluate(7, on_uncertain: ->(_r) {}, strict_confidence: true) }
        .to raise_error(IsEvenAI::UncertainParityError)
    end

    it "falls through to the best guess when on_uncertain only observes" do
      calls = []
      result = described_class.evaluate(7, on_uncertain: ->(r) { calls << r })
      expect(calls.size).to eq(1)
      expect(result).to have_attributes(uncertain?: true, even?: true)
    end

    it "raises UncertainParityError in strict mode with nothing to resolve it" do
      expect { described_class.evaluate(7, strict_confidence: true) }.to raise_error(IsEvenAI::UncertainParityError, /uncertain/)
    end

    it "resolves to probability >= 0.5 when not strict" do
      expect(described_class.evaluate(7)).to have_attributes(uncertain?: true, even?: true)
    end
  end

  describe "caching" do
    it "is off by default" do
      stub = stub_jev(jev_noul_body(0.99))
      2.times { described_class.even?(2) }
      expect(stub).to have_been_requested.twice
    end

    it "serves repeats from the shared in-memory cache when true" do
      stub = stub_jev(jev_noul_body(0.99))
      first = described_class.evaluate(2, cache: true)
      second = described_class.evaluate(2, cache: true)
      expect(stub).to have_been_requested.once
      expect(second).to equal(first)
    end

    it "keys on input, type and options" do
      stub = stub_jev(jev_noul_body(0.99))
      described_class.evaluate(2, cache: true)
      described_class.evaluate(4, cache: true)
      described_class.evaluate("2", cache: true, allow_non_integer: true)
      described_class.evaluate(2, cache: true, yes_threshold: 0.9)
      expect(stub).to have_been_requested.times(4)
    end

    it "does not cache failures" do
      stub_jev(status: 400, body: "{}")
      2.times { expect { described_class.evaluate(2, cache: true) }.to raise_error(IsEvenAI::APIError) }
      expect(a_request(:post, "https://api.typesafe.ai/v1/systemone")).to have_been_made.twice
    end

    it "can be cleared" do
      stub = stub_jev(jev_noul_body(0.99))
      described_class.evaluate(2, cache: true)
      described_class.clear_cache!
      described_class.evaluate(2, cache: true)
      expect(stub).to have_been_requested.twice
    end

    it "accepts a custom store" do
      store = Class.new do
        def initialize = @data = {}
        def read(key) = @data[key]
        def write(key, value) = @data[key] = value
      end.new
      stub = stub_jev(jev_noul_body(0.99))
      2.times { described_class.even?(2, cache: store) }
      expect(stub).to have_been_requested.once
    end

    it "rejects stores that cannot read and write" do
      expect { described_class.even?(2, cache: Object.new) }.to raise_error(IsEvenAI::ConfigurationError, /cache/)
    end
  end

  describe IsEvenAI::Cache do
    it "evicts the oldest entry beyond max_size and is thread-safe" do
      cache = described_class.new(max_size: 2)
      cache.write(:a, 1)
      cache.write(:b, 2)
      cache.write(:c, 3)
      expect([cache.read(:a), cache.read(:b), cache.read(:c)]).to eq([nil, 2, 3])
      expect(cache.size).to eq(2)

      threads = Array.new(8) { |i| Thread.new { 50.times { |j| cache.write(:"k#{i}-#{j}", j) } } }
      threads.each(&:join)
      expect(cache.size).to eq(2)
    end
  end

  describe IsEvenAI::Providers::Registry do
    it "lists the five built-in providers" do
      expect(described_class.names).to include(:jev, :openai, :anthropic, :gemini, :openai_compatible)
    end

    it "supports custom providers" do
      custom = Class.new(IsEvenAI::Providers::Base) do
        def self.provider_name = :oracle

        def call(input) = IsEvenAI::Result.new(input: input, even: input.even?, provider: name)
      end
      described_class.register(:oracle, custom)

      expect(IsEvenAI.even?(4, provider: :oracle)).to be(true)
      expect(IsEvenAI.odd?(4, provider: :oracle)).to be(false)
    ensure
      described_class.instance_variable_get(:@providers).delete(:oracle)
    end

    it "raises for unknown providers" do
      expect { described_class.fetch(:nope) }.to raise_error(IsEvenAI::ConfigurationError, /Unknown provider/)
    end
  end

  describe "error hierarchy" do
    it "descends from IsEvenAI::Error" do
      expect([IsEvenAI::ConfigurationError, IsEvenAI::InvalidInputError, IsEvenAI::APIError, IsEvenAI::ParseError, IsEvenAI::UncertainParityError]).to all(be < IsEvenAI::Error)
      expect(IsEvenAI::RateLimitError).to be < IsEvenAI::APIError
      expect(IsEvenAI::Error).to be < StandardError
    end
  end

  describe "Result" do
    it "defaults sensibly" do
      result = IsEvenAI::Result.new(input: 1, even: false, provider: :x)
      expect(result).to have_attributes(odd?: true, uncertain?: false, escalated?: false, non_integer?: false, raw: {}, latency_ms: 0.0)
    end
  end
end
