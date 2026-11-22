# frozen_string_literal: true

module IsEvenAI
  module Providers
    # TypeSafe AI "System One" (Jev). Wire schemas follow RESEARCH.md section 2.3.
    #
    # Documented response shapes:
    #   noul   -> { "type" => "noul", "noul" => 0.99 }              (no confidence field)
    #   choice -> { "type", "choice", "confidence", "probabilities" }
    #   score  -> { "type", "score", "confidence", "probabilities", "legend" }
    class Jev < Base
      DEFAULT_BASE_URL = "https://api.typesafe.ai"
      PATH = "/v1/systemone"

      PRIMARY_KEYS = { noul: "is_even", choice: "parity", score: "evenness" }.freeze

      SCORE_RUBRIC = [
        "Aggressively odd — unmistakably not divisible by 2",
        "Probably odd — leans strongly away from evenness",
        "Numerically ambiguous — parity cannot be confidently established",
        "Probably even — strongly exhibits evenness",
        "Unquestionably even — textbook divisible by 2"
      ].freeze

      def self.provider_name = :jev

      def default_model = "jev-latest"

      def call(input)
        body = http.post_json(
          endpoint(DEFAULT_BASE_URL, PATH),
          request_body(input),
          "Authorization" => "Bearer #{api_key!}"
        )
        build_result(input, body)
      end

      private

      def primitive = config.primitive

      def primary_key = PRIMARY_KEYS.fetch(primitive)

      def request_body(input)
        { "model" => model, "state" => state(input), "questions" => questions(input) }
      end

      def state(input)
        return { "value" => serialize_value(input) } unless non_integer?(input)

        {
          "value" => serialize_value(input),
          "ruby_type" => input.class.name,
          "non_integer_override" => true
        }
      end

      def questions(input)
        questions = { primary_key => primary_question(input) }
        questions.merge!(fan_out_questions) if config.fan_out
        questions
      end

      def primary_question(input)
        case primitive
        when :noul then noul_question(input)
        when :choice then choice_question(input)
        when :score then score_question(input)
        end
      end

      def noul_question(input)
        return { "type" => "noul", "instructions" => "Is `value` an even integer (divisible by 2 with no remainder)?" } unless non_integer?(input)

        {
          "type" => "noul",
          "instructions" => "Does `value` semantically represent an even integer? It may be a number word, a string, a float or any other object; `ruby_type` says what it was in Ruby.",
          "criteria" => {
            "true" => "Represents an integer divisible by 2 with remainder 0, e.g. \"42\", \"forty-two\", 4.0, \"a dozen\"",
            "false" => "Represents an odd integer or is not an integer at all, e.g. \"a baker's dozen\", 4.5, \"banana\", infinity"
          }
        }
      end

      # Documented choice: "even" / "odd", plus "not_an_integer" only when the override is on,
      # so the model has somewhere to put non-integers instead of splitting probability across even/odd.
      def choice_question(_input)
        criteria = {
          "even" => "An integer evenly divisible by 2",
          "odd" => "An integer not divisible by 2"
        }
        criteria["not_an_integer"] = "A float, non-numeric string, or invalid number" if config.allow_non_integer
        { "type" => "choice", "instructions" => "What is the parity of `value`?", "criteria" => criteria }
      end

      def score_question(_input)
        { "type" => "score", "instructions" => "How even is `value`?", "criteria" => SCORE_RUBRIC }
      end

      def fan_out_questions
        questions = {
          "is_odd" => { "type" => "noul", "instructions" => "Is `value` an odd integer (not divisible by 2)?" },
          "is_suspiciously_large" => { "type" => "noul", "instructions" => "Is `value` a suspiciously large number?" }
        }
        questions["represents_integer"] = { "type" => "noul", "instructions" => "Does `value` represent an integer of any kind?" } if config.allow_non_integer
        questions
      end

      def build_result(input, body)
        answers = body["answers"]
        raise ParseError, "jev response has no answers: #{body.to_s[0, 200]}" unless answers.is_a?(Hash)

        answer = answers[primary_key]
        raise ParseError, "jev response is missing the #{primary_key.inspect} answer" unless answer.is_a?(Hash)

        attributes = send(:"parse_#{primitive}", answer)
        Result.new(
          input: input, provider: name, model: body["model"] || model, primitive: primitive,
          non_integer: non_integer?(input), usage: symbolize_usage(body["usage"]),
          fan_out: config.fan_out ? parse_fan_out(answers) : nil, raw: body, **attributes
        )
      end

      def parse_noul(answer)
        probability = number!(answer["noul"], "noul")
        even, uncertain = decide(probability)
        { even: even, uncertain: uncertain, probability: probability, confidence: ((2 * probability) - 1).abs }
      end

      def parse_choice(answer)
        choice = answer["choice"]
        probabilities = answer["probabilities"]
        raise ParseError, "jev choice answer is missing choice/probabilities" unless choice.is_a?(String) && probabilities.is_a?(Hash)

        probability = number!(probabilities["even"], "probabilities.even")
        confidence = answer["confidence"].is_a?(Numeric) ? answer["confidence"].to_f : nil
        if choice == "not_an_integer"
          return { even: false, uncertain: true, probability: probability, confidence: confidence,
                   reasoning: "Jev classified the input as not an integer" }
        end

        even, uncertain = decide(probability)
        { even: even, uncertain: uncertain, probability: probability, confidence: confidence }
      end

      def parse_score(answer)
        score = number!(answer["score"], "score")
        normalized = (score / (SCORE_RUBRIC.size - 1)).clamp(0.0, 1.0)
        even, uncertain = decide(normalized)
        confidence = answer["confidence"].is_a?(Numeric) ? answer["confidence"].to_f : nil
        {
          even: even, uncertain: uncertain, probability: normalized, confidence: confidence,
          reasoning: SCORE_RUBRIC[score.round.clamp(0, SCORE_RUBRIC.size - 1)]
        }
      end

      def parse_fan_out(answers)
        (answers.keys - [primary_key]).to_h do |key|
          value = answers[key]
          [key.to_sym, value.is_a?(Hash) && value["noul"].is_a?(Numeric) ? value["noul"].to_f : nil]
        end
      end

      def number!(value, label)
        return value.to_f if value.is_a?(Numeric)

        raise ParseError, "jev answer #{label} is not a number: #{value.inspect}"
      end

      def symbolize_usage(usage)
        return nil unless usage.is_a?(Hash)

        token_usage(usage["input_tokens"], usage["output_tokens"])
      end
    end

    Registry.register(:jev, Jev)
  end
end
