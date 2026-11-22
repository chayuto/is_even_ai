# frozen_string_literal: true

require "stringio"

RSpec.describe IsEvenAI::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run_cli(*argv)
    described_class.start(argv, out: out, err: err)
  end

  before { ENV["TYPESAFE_API_KEY"] = "jev-key" }

  it "exits 0 for even and prints even" do
    stub_jev(jev_noul_body(0.99))
    expect(run_cli("42")).to eq(0)
    expect(out.string).to eq("even\n")
  end

  it "exits 1 for odd" do
    stub_jev(jev_noul_body(0.01))
    expect(run_cli("41")).to eq(1)
    expect(out.string).to eq("odd\n")
  end

  it "handles negative integers" do
    stub = stub_jev(jev_noul_body(0.99))
    expect(run_cli("-42")).to eq(0)
    expect(stub).to have_been_requested
  end

  it "exits 2 with a hint for non-integers" do
    expect(run_cli("forty-two")).to eq(2)
    expect(err.string).to include("--allow-non-integer")
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it "passes raw strings through with --allow-non-integer" do
    stub = stub_request(:post, "https://api.typesafe.ai/v1/systemone")
           .with { |r| JSON.parse(r.body)["state"] == { "value" => "forty-two", "ruby_type" => "String", "non_integer_override" => true } }
           .to_return(json_response(jev_noul_body(0.97)))
    expect(run_cli("forty-two", "--allow-non-integer")).to eq(0)
    expect(stub).to have_been_requested
  end

  it "accepts short flags and decimals with -a" do
    stub_jev(jev_noul_body(0.01))
    expect(run_cli("-a", "4.5")).to eq(1)
  end

  it "exits 2 on uncertain parity with --strict-confidence" do
    stub_jev(jev_noul_body(0.5))
    expect(run_cli("7", "--strict-confidence")).to eq(2)
    expect(err.string).to include("uncertain")
  end

  it "exits 2 on API errors" do
    stub_jev(status: 401, body: "{}")
    expect(run_cli("7")).to eq(2)
    expect(err.string).to include("is_even_ai:")
  end

  it "exits 2 on configuration errors" do
    ENV.delete("TYPESAFE_API_KEY")
    expect(run_cli("7")).to eq(2)
    expect(err.string).to include("No provider configured")
  end

  it "exits 2 on unknown options and missing values" do
    expect(run_cli("--bogus", "7")).to eq(2)
    expect(run_cli).to eq(2)
    expect(run_cli("1", "2")).to eq(2)
  end

  it "exits 2 for unknown providers" do
    expect(run_cli("7", "--provider", "cohere")).to eq(2)
    expect(err.string).to include("Unknown provider")
  end

  it "forwards provider, model, primitive, base-url and fan-out options" do
    body = { "model" => "m", "answers" => { "parity" => { "type" => "choice", "choice" => "even", "confidence" => 1.0, "probabilities" => { "even" => 0.99, "odd" => 0.01 } },
                                            "is_odd" => { "type" => "noul", "noul" => 0.0 }, "is_suspiciously_large" => { "type" => "noul", "noul" => 0.0 } } }
    stub = stub_request(:post, "http://jev.test/v1/systemone")
           .with { |r| JSON.parse(r.body).then { |b| b["model"] == "jev-1.13.0" && b["questions"].key?("parity") && b["questions"].key?("is_odd") } }
           .to_return(json_response(body))
    code = run_cli("42", "-p", "jev", "-m", "jev-1.13.0", "--primitive", "choice", "--base-url", "http://jev.test", "--fan-out")
    expect(code).to eq(0)
    expect(stub).to have_been_requested
  end

  it "escalates with --fallback-provider" do
    ENV["ANTHROPIC_API_KEY"] = "ant"
    stub_jev(jev_noul_body(0.5))
    stub_request(:post, "https://api.anthropic.com/v1/messages").to_return(json_response(anthropic_body(generative_answer(is_even: false))))
    expect(run_cli("7", "--fallback-provider", "anthropic", "--json")).to eq(1)
    expect(JSON.parse(out.string)).to include("provider" => "anthropic", "escalated" => true)
  end

  it "prints machine-readable output with --json" do
    stub_jev(jev_noul_body(0.99))
    expect(run_cli("42", "--json")).to eq(0)
    expect(JSON.parse(out.string)).to include("input" => 42, "even" => true, "odd" => false, "provider" => "jev", "primitive" => "noul")
  end

  it "prints diagnostics with --verbose" do
    stub_jev(jev_noul_body(0.99, extra_answers: { "is_odd" => { "type" => "noul", "noul" => 0.01 }, "is_suspiciously_large" => { "type" => "noul", "noul" => 0.0 } }))
    expect(run_cli("42", "-v", "--fan-out")).to eq(0)
    expect(out.string).to include("even", "model:       jev-1.14.0", "probability: 0.99", "confidence:", "latency:", "fan_out:")
  end

  it "prints reasoning for generative providers" do
    ENV["OPENAI_API_KEY"] = "sk"
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(json_response(openai_body(generative_answer(is_even: true))))
    expect(run_cli("42", "-p", "openai", "--verbose")).to eq(0)
    expect(out.string).to include("reasoning:   Because arithmetic.")
  end

  describe "--benchmark" do
    it "compares native modulo with the AI provider" do
      stub_jev(jev_noul_body(0.99))
      expect(run_cli("42", "--benchmark")).to eq(0)
      expect(out.string).to include("Method", "Integer#even? (n % 2 == 0)", "jev (jev-1.14.0, noul)", "Overhead", "enterprise-ready")
      expect(out.string).to match(/~[\d,]+x/)
    end

    it "marks native as n/a for non-integers" do
      stub_jev(jev_noul_body(0.01))
      expect(run_cli("banana", "-a", "--benchmark")).to eq(1)
      expect(out.string).to include("n/a")
    end
  end

  it "prints the version" do
    expect(run_cli("--version")).to eq(0)
    expect(out.string).to eq("is_even_ai #{IsEvenAI::VERSION}\n")
  end

  it "prints help" do
    expect(run_cli("--help")).to eq(0)
    expect(out.string).to include("Usage: is_even_ai", "--allow-non-integer", "--benchmark", "Exit codes")
  end
end
