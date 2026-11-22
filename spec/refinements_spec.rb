# frozen_string_literal: true

RSpec.describe IsEvenAI::Refinements do
  using described_class

  before { ENV["TYPESAFE_API_KEY"] = "k" }

  it "adds ai_even? / ai_odd? to Integer" do
    stub_jev(jev_noul_body(0.99))
    expect(42.ai_even?).to be(true)
    expect(42.ai_odd?).to be(false)
  end

  it "forces the jev provider with jev_even? / jev_odd?" do
    ENV.delete("TYPESAFE_API_KEY")
    IsEvenAI.configure do |c|
      c.provider = :openai
      c.api_key = "ignored-by-jev-call"
    end
    stub = stub_jev(jev_noul_body(0.01))
    expect(7.jev_even?).to be(false)
    expect(7.jev_odd?).to be(true)
    expect(stub).to have_been_requested.twice
  end

  it "requires allow_non_integer for Strings" do
    expect { "forty-two".ai_even? }.to raise_error(IsEvenAI::InvalidInputError, /allow_non_integer/)

    stub_jev(jev_noul_body(0.97))
    expect("forty-two".ai_even?(allow_non_integer: true)).to be(true)
  end

  it "supports Floats via the Numeric refinement" do
    expect { 4.0.ai_even? }.to raise_error(IsEvenAI::InvalidInputError)
    stub_jev(jev_noul_body(0.9))
    expect(4.0.ai_even?(allow_non_integer: true)).to be(true)
  end

  it "does not leak onto core classes outside the refinement scope" do
    expect(Integer.method_defined?(:ai_even?)).to be(false)
    expect(String.method_defined?(:ai_even?)).to be(false)
    expect(Object.method_defined?(:ai_even?)).to be(false)
  end
end
