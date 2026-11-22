# frozen_string_literal: true

require_relative "lib/is_even_ai/version"

Gem::Specification.new do |spec|
  spec.name = "is_even_ai"
  spec.version = IsEvenAI::VERSION
  spec.authors = ["Chayut Orapinpatipat"]
  spec.email = ["chayut_o@hotmail.com"]

  spec.summary = "Determine integer parity with TypeSafe Jev, OpenAI, Anthropic Claude, Google Gemini, or any OpenAI-compatible endpoint"
  spec.description = "A deadpan, production-grade parody Ruby gem that answers whether an integer is even by asking a " \
                     "System One decision model (TypeSafe Jev) or a frontier LLM instead of computing n % 2. Features " \
                     "calibrated confidence gating, System 1 to System 2 escalation, opt-in refinements, and a CLI. " \
                     "Zero runtime dependencies. Part of the vibe-sort series."
  spec.homepage = "https://github.com/chayuto/is_even_ai"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/is_even_ai"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["{lib,exe}/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md", "CODE_OF_CONDUCT.md"].select { |f| File.file?(f) }
  spec.bindir = "exe"
  spec.executables = ["is_even_ai"]
  spec.require_paths = ["lib"]

  # Runtime dependencies: none. Ruby stdlib only.
end
