# frozen_string_literal: true

RSpec.describe IsEvenAI::Configuration do
  subject(:config) { described_class.new }

  it "has deadpan defaults" do
    expect(config).to have_attributes(
      provider: nil, jev_primitive: :noul, yes_threshold: 0.7, no_threshold: 0.3,
      strict_confidence: false, allow_non_integer: false, cache: false, open_timeout: 5,
      read_timeout: 30, max_retries: 2, fallback_options: {}
    )
  end

  describe "provider auto-detection" do
    it "prefers IS_EVEN_AI_PROVIDER" do
      ENV["IS_EVEN_AI_PROVIDER"] = "gemini"
      ENV["TYPESAFE_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:gemini)
    end

    it "walks the documented key order" do
      expect { config.resolved_provider }.to raise_error(IsEvenAI::ConfigurationError, /No provider configured/)

      ENV["IS_EVEN_AI_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:openai_compatible)
      ENV["GOOGLE_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:gemini)
      ENV["ANTHROPIC_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:anthropic)
      ENV["OPENAI_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:openai)
      ENV["TYPESAFE_API_KEY"] = "k"
      expect(config.resolved_provider).to eq(:jev)
    end

    it "ignores blank variables" do
      ENV["TYPESAFE_API_KEY"] = "  "
      expect { config.resolved_provider }.to raise_error(IsEvenAI::ConfigurationError)
    end

    it "lets an explicit provider win" do
      ENV["TYPESAFE_API_KEY"] = "k"
      config.provider = "openai"
      expect(config.resolved_provider).to eq(:openai)
    end
  end

  describe "API key resolution" do
    it "reads the per-provider variable" do
      ENV["TYPESAFE_API_KEY"] = "jev-key"
      ENV["ANTHROPIC_API_KEY"] = "claude-key"
      expect(config.resolved_api_key(:jev)).to eq("jev-key")
      expect(config.resolved_api_key(:anthropic)).to eq("claude-key")
    end

    it "prefers GEMINI_API_KEY over GOOGLE_API_KEY" do
      ENV["GOOGLE_API_KEY"] = "google"
      expect(config.resolved_api_key(:gemini)).to eq("google")
      ENV["GEMINI_API_KEY"] = "gemini"
      expect(config.resolved_api_key(:gemini)).to eq("gemini")
    end

    it "falls back from OPENAI_API_KEY to IS_EVEN_AI_API_KEY for openai_compatible" do
      ENV["IS_EVEN_AI_API_KEY"] = "generic"
      expect(config.resolved_api_key(:openai_compatible)).to eq("generic")
      ENV["OPENAI_API_KEY"] = "openai"
      expect(config.resolved_api_key(:openai_compatible)).to eq("openai")
    end

    it "prefers an explicit api_key and allows nil" do
      config.api_key = "explicit"
      ENV["TYPESAFE_API_KEY"] = "env"
      expect(config.resolved_api_key(:jev)).to eq("explicit")
      expect(described_class.new.resolved_api_key(:openai_compatible)).to be_nil
    end
  end

  describe "base URL resolution" do
    it "uses TYPESAFE_BASE_URL then IS_EVEN_AI_BASE_URL for jev" do
      ENV["IS_EVEN_AI_BASE_URL"] = "http://generic"
      expect(config.resolved_base_url(:jev)).to eq("http://generic")
      ENV["TYPESAFE_BASE_URL"] = "http://typesafe"
      expect(config.resolved_base_url(:jev)).to eq("http://typesafe")
    end

    it "does not hand IS_EVEN_AI_BASE_URL to hosted providers" do
      ENV["IS_EVEN_AI_BASE_URL"] = "http://generic"
      expect(config.resolved_base_url(:openai)).to be_nil
      expect(config.resolved_base_url(:openai_compatible)).to eq("http://generic")
    end

    it "prefers an explicit base_url" do
      ENV["TYPESAFE_BASE_URL"] = "http://typesafe"
      config.base_url = "http://explicit"
      expect(config.resolved_base_url(:jev)).to eq("http://explicit")
    end
  end

  describe "#merge" do
    it "applies per-call overrides without touching the original" do
      merged = config.merge(provider: :openai, primitive: :score, yes_threshold: 0.9)
      expect(merged).to have_attributes(provider: :openai, jev_primitive: :score, yes_threshold: 0.9)
      expect(config).to have_attributes(provider: nil, jev_primitive: :noul, yes_threshold: 0.7)
    end

    it "rejects unknown options" do
      expect { config.merge(colour: "blue") }.to raise_error(IsEvenAI::ConfigurationError, /Unknown option :colour/)
    end
  end

  describe "#validate!" do
    it "rejects unknown providers" do
      expect { config.merge(provider: :cohere) }.to raise_error(IsEvenAI::ConfigurationError, /Unknown provider :cohere/)
      expect { config.merge(fallback_provider: :cohere) }.to raise_error(IsEvenAI::ConfigurationError, /fallback_provider/)
    end

    it "rejects unknown primitives" do
      expect { config.merge(primitive: :box) }.to raise_error(IsEvenAI::ConfigurationError, /jev_primitive/)
    end

    it "rejects invalid thresholds" do
      expect { config.merge(yes_threshold: 1.5) }.to raise_error(IsEvenAI::ConfigurationError, /between/)
      expect { config.merge(yes_threshold: 0.2, no_threshold: 0.4) }.to raise_error(IsEvenAI::ConfigurationError, /must not exceed/)
    end

    it "rejects bad timeouts, retries and fallback options" do
      expect { config.merge(read_timeout: 0) }.to raise_error(IsEvenAI::ConfigurationError, /read_timeout/)
      expect { config.merge(max_retries: -1) }.to raise_error(IsEvenAI::ConfigurationError, /max_retries/)
      expect { config.merge(fallback_options: "x") }.to raise_error(IsEvenAI::ConfigurationError, /fallback_options/)
    end
  end

  describe "#fallback_config" do
    it "isolates the fallback from the primary provider's credentials" do
      config.provider = :jev
      config.api_key = "jev-key"
      config.model = "jev-latest"
      config.base_url = "http://jev"
      config.fallback_provider = :anthropic
      config.fallback_options = { model: "claude-opus-5-5" }
      config.strict_confidence = true

      fallback = config.fallback_config
      expect(fallback).to have_attributes(
        provider: :anthropic, api_key: nil, model: "claude-opus-5-5", base_url: nil,
        fallback_provider: nil, strict_confidence: false, on_uncertain: nil
      )
    end
  end

  it "redacts the API key when inspected" do
    config.api_key = "sk-super-secret"
    expect(config.inspect).to include("[REDACTED]")
    expect(config.inspect).not_to include("sk-super-secret")
  end
end
