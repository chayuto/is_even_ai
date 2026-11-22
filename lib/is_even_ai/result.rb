# frozen_string_literal: true

module IsEvenAI
  Result = Data.define(
    :input, :even, :uncertain, :non_integer, :probability, :confidence, :provider, :model,
    :primitive, :escalated, :reasoning, :fan_out, :latency_ms, :usage, :raw
  ) do
    def initialize(input:, even:, provider:, uncertain: false, non_integer: false, probability: nil, confidence: nil,
                   model: nil, primitive: nil, escalated: false, reasoning: nil, fan_out: nil, latency_ms: 0.0,
                   usage: nil, raw: {})
      super
    end

    def even? = even == true
    def odd? = !even?
    def uncertain? = uncertain == true
    def non_integer? = non_integer == true
    def escalated? = escalated == true

    # Serializable hash (inputs that are not JSON-native are stringified).
    def to_h
      super.merge(input: serializable_input, even: even?, odd: odd?)
    end

    private

    def serializable_input
      case input
      when Integer, String, true, false then input
      when Float then input.finite? ? input : input.to_s
      else input.to_s
      end
    end
  end
end
