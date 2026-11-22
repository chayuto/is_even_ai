# IsEvenAI

> **Why rely on legacy modulo arithmetic from the 1970s when you can determine integer parity using frontier LLMs or calibrated System One probabilistic decision models?**

[![Gem Version](https://badge.fury.io/rb/is_even_ai.svg)](https://badge.fury.io/rb/is_even_ai)
[![CI](https://github.com/chayuto/is_even_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/chayuto/is_even_ai/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`is_even_ai` is a production-grade, zero-dependency Ruby gem that answers one question with the seriousness it deserves: *is this integer even?* It supports TypeSafe AI's **Jev** (System One), OpenAI, Anthropic Claude, Google Gemini, and any OpenAI-compatible endpoint (Ollama, Groq, OpenRouter, ...).

It is part of the same series as [`vibe-sort`](https://rubygems.org/gems/vibe-sort).

## Disclaimer

This is a parody and educational project. `n.even?` is faster, free, offline, and correct. Please keep using it.

## Benchmark

| Method | Latency | Cost per 1M checks | Notes |
| :-- | :-- | :-- | :-- |
| `Integer#even?` (`n % 2 == 0`) | ~19 ns (measured, Ruby 3.3, Apple Silicon) | $0.00 | Deterministic. Works on a plane. |
| TypeSafe Jev `noul` | not published (see below) | **$4.20** | 159-byte minimal request, free output tokens |
| `gemini-2.5-flash-lite` (legacy) | not measured | $11.20 | |
| `gpt-6-luna`, `claude-haiku-5-5` | not measured | $12.00 | Lean, non-reasoning configuration |
| Frontier reasoning models, default thinking | not measured | up to $5,040.00 | The most expensive way to learn that 42 is even |

Cost figures are modeled in [RESEARCH.md](RESEARCH.md) (100 input tokens for Jev; 80 input and 8 to 110 output tokens for generative models). TypeSafe publishes no latency SLA, and this repository ships no network latency numbers it has not measured. Run `is_even_ai 42 --benchmark` against your own account to get yours.

## Architecture

```text
                 +--------------------+
   42 ---------> |  System 1: Jev     |   calibrated probability p
                 |  (noul/choice/score)|
                 +---------+----------+
                           |
                 +---------v----------+
                 |  Confidence Gate   |   p >= yes_threshold (0.7)  -> even
                 |  0.3 < p < 0.7 ?   |   p <= no_threshold  (0.3)  -> odd
                 +----+----------+----+
              certain |          | uncertain
                      v          v
                  Result   +-----+---------------------------+
                           | fallback_provider configured?   |
                           +--+------------------------+-----+
                          yes |                        | no
                              v                        v
                  +-----------+----------+   +---------+----------------+
                  | System 2: frontier   |   | on_uncertain proc        |
                  | LLM (:anthropic ...) |   | (human in the loop)      |
                  +-----------+----------+   +---------+----------------+
                              |                        | unresolved
                              v                        v
                           Result              strict_confidence ?
                       (escalated: true)       raise UncertainParityError
                                               otherwise p >= 0.5
```

## Installation

```ruby
gem "is_even_ai"
```

```bash
bundle install   # or: gem install is_even_ai
```

Requires Ruby 3.2 or newer. No runtime dependencies: the HTTP client is `Net::HTTP`.

## Quick Start

```bash
export TYPESAFE_API_KEY="..."
```

```ruby
require "is_even_ai"

IsEvenAI.even?(42)   # => true
IsEvenAI.odd?(42)    # => false

result = IsEvenAI.evaluate(42)
result.even?         # => true
result.probability   # => 0.99
result.confidence    # => 0.98
result.uncertain?    # => false
result.model         # => "jev-1.14.0"
result.latency_ms    # => 183.4
result.to_h          # => serializable Hash
```

With no `provider:` set, the provider is detected from `IS_EVEN_AI_PROVIDER`, then the first of `TYPESAFE_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` / `GOOGLE_API_KEY`, `IS_EVEN_AI_API_KEY`.

### Configuration

```ruby
IsEvenAI.configure do |config|
  config.provider = :jev              # :jev, :openai, :anthropic, :gemini, :openai_compatible
  config.api_key = nil                # resolved from the provider's environment variable
  config.model = nil                  # provider default
  config.base_url = nil               # proxy, LiteLLM, OpenRouter, Ollama, Semlf...
  config.jev_primitive = :noul        # :noul, :choice, :score
  config.yes_threshold = 0.7
  config.no_threshold = 0.3
  config.strict_confidence = false    # true raises UncertainParityError in the gray zone
  config.allow_non_integer = false
  config.fallback_provider = nil      # System 1 -> System 2 escalation
  config.fallback_options = {}        # model / api_key overrides for the fallback
  config.on_uncertain = nil           # ->(result) { ... } human-in-the-loop hook
  config.cache = false                # true, or any object with #read and #write
  config.open_timeout = 5
  config.read_timeout = 30
  config.max_retries = 2
end
```

Every option can also be passed per call (`primitive:` is an alias of `jev_primitive:`).

### Providers

| Provider | Default model | Environment variable | Endpoint |
| :-- | :-- | :-- | :-- |
| `:jev` | `jev-latest` | `TYPESAFE_API_KEY` | `POST https://api.typesafe.ai/v1/systemone` |
| `:openai` | `gpt-6-luna` | `OPENAI_API_KEY` | `POST https://api.openai.com/v1/responses` |
| `:anthropic` | `claude-haiku-5-5` | `ANTHROPIC_API_KEY` | `POST https://api.anthropic.com/v1/messages` |
| `:gemini` | `gemini-3.5-flash-lite` | `GEMINI_API_KEY`, then `GOOGLE_API_KEY` | `.../v1beta/models/{model}:generateContent` |
| `:openai_compatible` | none (required) | `OPENAI_API_KEY`, then `IS_EVEN_AI_API_KEY` | `{base_url}/chat/completions` |

```ruby
# Jev: three decision primitives, all in one calibrated round trip
IsEvenAI.even?(42)                                  # noul: a probability
IsEvenAI.evaluate(42, primitive: :choice)           # even / odd with probabilities
IsEvenAI.evaluate(42, primitive: :score)            # five-level "vibe evenness" rubric
IsEvenAI.evaluate(42, fan_out: true).fan_out        # => { is_odd: 0.01, is_suspiciously_large: 0.02 }

# Frontier models
IsEvenAI.even?(42, provider: :openai, model: "gpt-6-luna")
IsEvenAI.even?(42, provider: :anthropic, model: "claude-fable-5-2")
IsEvenAI.even?(42, provider: :gemini)

# Anything that speaks Chat Completions
IsEvenAI.even?(42, provider: :openai_compatible, base_url: "http://localhost:11434/v1", model: "llama3.2") # Ollama, no key needed
IsEvenAI.even?(42, provider: :openai_compatible, base_url: "https://openrouter.ai/api/v1", model: "typesafe/jev-router")

# Jev-compatible servers (LiteLLM pass-through, self-hosted, ...)
IsEvenAI.even?(42, provider: :jev, base_url: "http://localhost:4000")
```

`IS_EVEN_AI_BASE_URL` is honoured for `:openai_compatible` and `:jev`; `TYPESAFE_BASE_URL` for `:jev`.

The `:choice` primitive offers `even` / `odd`, and adds `not_an_integer` only when `allow_non_integer` is on, so a non-integer has somewhere to go besides splitting probability between the two real answers. With `fan_out: true` and `allow_non_integer: true` the same request also asks `represents_integer`.

### Confidence gating and escalation

```ruby
IsEvenAI.configure do |config|
  config.fallback_provider = :anthropic
  config.fallback_options = { model: "claude-opus-5-5" }
  config.on_uncertain = ->(result) { page_a_human(result) }  # used when there is no fallback_provider
  config.strict_confidence = true                            # raise instead of guessing
end

result = IsEvenAI.evaluate(7)
result.escalated?                 # => true when System 2 answered
result.raw[:escalated_from]       # => the original Jev result, as a Hash
```

Jev `noul` returns a probability. At or above `yes_threshold` the integer is even; at or below `no_threshold` it is odd; in between the result is `uncertain?`. The resolution order for an uncertain result is: `fallback_provider`, then `on_uncertain` (a returned `Result` wins; anything else falls through), then `UncertainParityError` if `strict_confidence` is on, otherwise a best guess at `probability >= 0.5`. Generative providers report their own confidence; at or below `no_threshold` it counts as uncertain.

## Non-Integer Override

By default only `Integer` is accepted. Everything else is rejected before any network call:

```ruby
IsEvenAI.even?("forty-two")
# => IsEvenAI::InvalidInputError: Expected an Integer but got String ("forty-two").
#    Pass allow_non_integer: true (or set config.allow_non_integer = true)
#    to let the AI judge non-integers anyway.
```

With `allow_non_integer: true`, any non-`nil` value is passed to the provider together with its Ruby class, and the model is asked whether it semantically represents an even integer:

```ruby
IsEvenAI.even?("42",              allow_non_integer: true)  # => true
IsEvenAI.even?("forty-two",       allow_non_integer: true)  # => true
IsEvenAI.even?(4.0,               allow_non_integer: true)  # => true
IsEvenAI.even?("a baker's dozen", allow_non_integer: true)  # => false (13)
IsEvenAI.even?("banana",          allow_non_integer: true)  # => false, with low confidence

IsEvenAI.even?("a baker's dozen", allow_non_integer: true, strict_confidence: true)
# => may raise IsEvenAI::UncertainParityError when the model is not sure
```

`result.non_integer?` records whether the override was needed. `nil` is always rejected. The answers above are what a sensible model should say, not recorded output: models are probabilistic, which is the whole joke.

## Refinements

Nothing is monkey-patched globally. Opt in per file:

```ruby
using IsEvenAI::Refinements

42.ai_even?                                    # configured provider
42.ai_odd?
42.jev_even?                                   # forces provider: :jev
42.jev_odd?
"forty-two".ai_even?(allow_non_integer: true)  # Strings need the override
```

## CLI

```bash
is_even_ai 42
is_even_ai "forty-two" --allow-non-integer
is_even_ai 42 --provider anthropic --model claude-haiku-5-5 --verbose
is_even_ai 42 --primitive choice --fan-out --json
is_even_ai 7 --fallback-provider anthropic --strict-confidence
is_even_ai 42 --benchmark
```

| Option | Description |
| :-- | :-- |
| `-p`, `--provider PROVIDER` | `jev`, `openai`, `anthropic`, `gemini`, `openai_compatible` |
| `-m`, `--model MODEL` | Model identifier |
| `--primitive PRIMITIVE` | `noul`, `choice`, `score` |
| `--base-url URL` | Custom endpoint |
| `-a`, `--allow-non-integer` | Pass the raw argument to the AI instead of requiring an integer |
| `--strict-confidence` | Fail when parity is uncertain |
| `--fan-out` | Extra Jev questions in the same request |
| `--fallback-provider PROVIDER` | Escalate uncertain answers |
| `--json` | Print `result.to_h` |
| `-v`, `--verbose` | Probability, confidence, model, latency, reasoning, fan-out |
| `--benchmark` | Native `n % 2 == 0` versus the AI provider |
| `--version`, `-h`, `--help` | |

Exit codes: `0` even, `1` odd, `2` error, uncertain parity (with `--strict-confidence`) or invalid input. Without `--allow-non-integer` the argument must match `/^-?\d+$/`.

Example `--benchmark` output (illustrative: your latency and overhead will differ):

```text
Method                      Result  Latency          Overhead
--------------------------  ------  ---------------  ----------
Integer#even? (n % 2 == 0)  even    0.000019 ms      1x
jev (jev-1.14.0, noul)      even    183.412000 ms    ~9,653,263x

Modulo arithmetic remains available. It is merely not enterprise-ready.
```

## Errors

`IsEvenAI::Error` is the base class. `ConfigurationError`, `InvalidInputError`, `APIError` (`status_code`, `response_body`, `provider`), `RateLimitError` (`retry_after`), `ParseError`, and `UncertainParityError` (`result`).

Requests are retried with exponential backoff and full jitter on timeouts and HTTP 429, 500, 502, 503, 504 and 529, honouring a numeric `Retry-After`. Billing-exhausted 429s and other 4xx responses fail immediately.

## Development

```bash
bundle install
bundle exec rake        # rspec + rubocop
```

All specs are WebMock-backed; no live network calls are made. Pre-release checks that need real API access are listed in [RESEARCH.md](RESEARCH.md) section 5.4.

## Contributing

Bug reports and pull requests are welcome at <https://github.com/chayuto/is_even_ai>. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE.txt](LICENSE.txt).

---

*Part of the series: [`vibe-sort`](https://rubygems.org/gems/vibe-sort) sorts arrays with AI. `is_even_ai` checks parity with AI. Next: `is_prime_ai`, presumably.*
