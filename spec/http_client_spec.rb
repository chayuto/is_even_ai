# frozen_string_literal: true

RSpec.describe IsEvenAI::HttpClient do
  subject(:client) { described_class.new(provider: :test, max_retries: 2) }

  let(:url) { "https://example.test/v1/thing" }
  let(:sleeps) { [] }

  before { described_class.sleeper = ->(seconds) { sleeps << seconds } }

  it "posts JSON with explicit Content-Type and returns parsed JSON" do
    stub = stub_request(:post, url)
           .with(headers: { "Content-Type" => "application/json", "Authorization" => "Bearer k" }, body: { "a" => 1 })
           .to_return(json_response("ok" => true))
    expect(client.post_json(url, { "a" => 1 }, "Authorization" => "Bearer k")).to eq("ok" => true)
    expect(stub).to have_been_requested.once
  end

  it "retries 5xx and then succeeds" do
    stub_request(:post, url).to_return({ status: 503, body: "busy" }, { status: 529, body: "overloaded" }, json_response("ok" => 1))
    expect(client.post_json(url, {})).to eq("ok" => 1)
    expect(sleeps.size).to eq(2)
  end

  it "raises APIError once retries are exhausted" do
    stub_request(:post, url).to_return(status: 500, body: JSON.generate("error" => { "message" => "kaboom" }))
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::APIError, /HTTP 500\): kaboom/) { |e|
      expect(e).to have_attributes(status_code: 500, provider: :test)
      expect(e.response_body).to include("kaboom")
    }
    expect(a_request(:post, url)).to have_been_made.times(3)
  end

  it "honours a numeric Retry-After on 429 (clamped) and raises RateLimitError" do
    stub_request(:post, url).to_return(status: 429, body: "slow down", headers: { "Retry-After" => "120" })
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::RateLimitError) { |e|
      expect(e.retry_after).to eq(120.0)
      expect(e.status_code).to eq(429)
    }
    expect(sleeps).to eq([30.0, 30.0])
  end

  it "does not retry billing-exhausted 429s" do
    stub_request(:post, url).to_return(status: 429, body: JSON.generate("error" => { "code" => "credit_balance_exhausted", "message" => "no credit" }))
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::RateLimitError, /no credit/)
    expect(a_request(:post, url)).to have_been_made.once
  end

  %w[400 401 403 404 413 422].each do |status|
    it "does not retry HTTP #{status}" do
      stub_request(:post, url).to_return(status: status.to_i, body: "nope")
      expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::APIError, /HTTP #{status}/)
      expect(a_request(:post, url)).to have_been_made.once
    end
  end

  it "retries timeouts and then raises APIError" do
    stub_request(:post, url).to_timeout
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::APIError, /request failed/)
    expect(a_request(:post, url)).to have_been_made.times(3)
  end

  it "recovers from a transient connection reset" do
    stub_request(:post, url).to_raise(Errno::ECONNRESET).then.to_return(json_response("ok" => 2))
    expect(client.post_json(url, {})).to eq("ok" => 2)
  end

  it "raises ParseError for malformed JSON" do
    stub_request(:post, url).to_return(status: 200, body: "<html>")
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::ParseError, /malformed JSON/)
  end

  it "raises ParseError when JSON is not an object" do
    stub_request(:post, url).to_return(status: 200, body: "[1,2]")
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::ParseError, /not an object/)
  end

  it "wraps connection failures without retrying" do
    stub_request(:post, url).to_raise(Errno::ECONNREFUSED)
    expect { client.post_json(url, {}) }.to raise_error(IsEvenAI::APIError, /connection failed/)
    expect(a_request(:post, url)).to have_been_made.once
  end

  it "uses the default sleeper when none is injected" do
    described_class.sleeper = nil
    expect(described_class.sleeper).to respond_to(:call)
  end
end
