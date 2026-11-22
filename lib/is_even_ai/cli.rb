# frozen_string_literal: true

require "optparse"

module IsEvenAI
  # Testable command-line interface. Exit codes: 0 even, 1 odd, 2 error / uncertain / invalid input.
  class CLI
    NATIVE_ITERATIONS = 100_000
    INTEGER_PATTERN = /\A-?\d+\z/
    SIGNED_NUMBER_PATTERN = /\A-\d+(\.\d+)?\z/

    def self.start(argv, out: $stdout, err: $stderr)
      new(argv, out: out, err: err).run
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {}
      @flags = { json: false, verbose: false, benchmark: false }
    end

    def run
      # Negative numbers look like options to OptionParser, so pull them out first.
      negatives, rest = @argv.partition { |arg| arg.match?(SIGNED_NUMBER_PATTERN) }
      args = parser.parse(rest) + negatives
      return @exit_now if @exit_now

      return fail_with("Expected exactly one value to check.\n#{parser.help}") unless args.size == 1

      input = parse_input(args.first)
      @flags[:benchmark] ? benchmark(input) : check(input)
    rescue OptionParser::ParseError => e
      fail_with("#{e.message}\n#{parser.help}")
    rescue IsEvenAI::Error => e
      fail_with(e.message)
    end

    private

    def check(input)
      result = IsEvenAI.evaluate(input, **@options)
      if @flags[:json]
        @out.puts JSON.pretty_generate(result.to_h)
      else
        @out.puts result.even? ? "even" : "odd"
        print_verbose(result) if @flags[:verbose]
      end
      result.even? ? 0 : 1
    end

    def parse_input(arg)
      return arg if @options[:allow_non_integer]
      return Integer(arg, 10) if arg.match?(INTEGER_PATTERN)

      raise InvalidInputError, "#{arg.inspect} is not an integer. Pass --allow-non-integer to let the AI judge it anyway."
    end

    def print_verbose(result)
      @out.puts "  provider:    #{result.provider}"
      @out.puts "  model:       #{result.model}"
      @out.puts "  primitive:   #{result.primitive || "-"}"
      @out.puts "  probability: #{result.probability.inspect}"
      @out.puts "  confidence:  #{result.confidence.inspect}"
      @out.puts "  uncertain:   #{result.uncertain?}"
      @out.puts "  escalated:   #{result.escalated?}"
      @out.puts "  latency:     #{format("%.3f", result.latency_ms)} ms"
      @out.puts "  reasoning:   #{result.reasoning}" if result.reasoning
      @out.puts "  fan_out:     #{result.fan_out.inspect}" if result.fan_out
    end

    def benchmark(input)
      native_ms = native_latency_ms(input)
      result = IsEvenAI.evaluate(input, **@options)
      rows = [
        ["Integer#even? (n % 2 == 0)", if native_ms
                                         input.even? ? "even" : "odd"
                                       else
                                         "n/a"
                                       end, native_ms, "1x"],
        ["#{result.provider} (#{result.model}#{", #{result.primitive}" if result.primitive})",
         result.even? ? "even" : "odd", result.latency_ms, overhead(result.latency_ms, native_ms)]
      ]
      print_table(rows)
      result.even? ? 0 : 1
    end

    def native_latency_ms(input)
      return nil unless input.is_a?(Integer)

      seconds = Benchmark.realtime { NATIVE_ITERATIONS.times { input.even? } }
      seconds * 1000.0 / NATIVE_ITERATIONS
    end

    def overhead(ai_ms, native_ms)
      return "n/a" unless native_ms&.positive?

      "~#{(ai_ms / native_ms).round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse}x"
    end

    def print_table(rows)
      headers = %w[Method Result Latency Overhead]
      cells = rows.map { |name, answer, ms, over| [name, answer, ms ? format("%.6f ms", ms) : "n/a", over] }
      widths = headers.each_index.map { |i| ([headers[i]] + cells.map { |row| row[i] }).map(&:length).max }
      line = ->(row) { row.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join("  ") }
      @out.puts line.call(headers)
      @out.puts widths.map { |w| "-" * w }.join("  ")
      cells.each { |row| @out.puts line.call(row) }
      @out.puts
      @out.puts "Modulo arithmetic remains available. It is merely not enterprise-ready."
    end

    def fail_with(message)
      @err.puts "is_even_ai: #{message}"
      2
    end

    def finish(code, text)
      @out.puts text
      @exit_now = code
    end

    def parser
      @parser ||= OptionParser.new do |o|
        o.banner = "Usage: is_even_ai [options] VALUE"
        o.separator ""
        o.separator "Exit codes: 0 even, 1 odd, 2 error or uncertain parity."
        o.separator ""
        o.on("-p", "--provider PROVIDER", "jev, openai, anthropic, gemini, openai_compatible") { |v| @options[:provider] = v.to_sym }
        o.on("-m", "--model MODEL", "Model identifier") { |v| @options[:model] = v }
        o.on("--primitive PRIMITIVE", "Jev primitive: noul, choice, score") { |v| @options[:primitive] = v.to_sym }
        o.on("--base-url URL", "Custom endpoint (proxy, OpenRouter, Ollama, Semlf...)") { |v| @options[:base_url] = v }
        o.on("-a", "--allow-non-integer", "Let the AI judge non-integers such as \"forty-two\"") { @options[:allow_non_integer] = true }
        o.on("--strict-confidence", "Fail with exit code 2 when parity is uncertain") { @options[:strict_confidence] = true }
        o.on("--fan-out", "Ask Jev extra questions in the same request") { @options[:fan_out] = true }
        o.on("--fallback-provider PROVIDER", "Escalate uncertain answers to this provider") { |v| @options[:fallback_provider] = v.to_sym }
        o.on("--json", "Print the full result as JSON") { @flags[:json] = true }
        o.on("-v", "--verbose", "Print probability, confidence, model, latency and reasoning") { @flags[:verbose] = true }
        o.on("--benchmark", "Compare native n % 2 == 0 with the configured AI provider") { @flags[:benchmark] = true }
        o.on("--version", "Show version") { finish(0, "is_even_ai #{VERSION}") }
        o.on("-h", "--help", "Show this help") { finish(0, o.help) }
      end
    end
  end
end
