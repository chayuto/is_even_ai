# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- `IsEvenAI.even?`, `IsEvenAI.odd?` and `IsEvenAI.evaluate` with full decision telemetry (`IsEvenAI::Result`).
- Providers: TypeSafe Jev (`noul`, `choice`, `score`, speculative `fan_out`), OpenAI (Responses API),
  Anthropic (Messages, 2026-10-21), Google Gemini (`generateContent`) and OpenAI-compatible endpoints
  (Ollama, Groq, OpenRouter, LiteLLM, ...), plus an extensible provider registry.
- Calibrated confidence gating (`yes_threshold` / `no_threshold`), `strict_confidence` and `UncertainParityError`.
- System 1 to System 2 escalation via `fallback_provider`, with the `on_uncertain` human-in-the-loop hook.
- Strict `Integer` input by default; `allow_non_integer: true` lets the AI judge `"forty-two"`, `4.0`, `"banana"`.
- Optional thread-safe in-memory cache or custom store.
- Stdlib HTTP client with timeouts and jittered retries on 429/5xx.
- Opt-in `IsEvenAI::Refinements` (`ai_even?`, `ai_odd?`, `jev_even?`, `jev_odd?`).
- `is_even_ai` CLI with `--json`, `--verbose` and `--benchmark`.
- Zero runtime dependencies.
