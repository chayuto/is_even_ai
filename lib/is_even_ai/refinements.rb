# frozen_string_literal: true

module IsEvenAI
  # Opt-in only. Nothing is monkey-patched globally:
  #
  #   using IsEvenAI::Refinements
  #   42.ai_even?
  module Refinements
    # Shared method bodies, imported into each refinement below.
    module Methods
      def ai_even?(**) = IsEvenAI.even?(self, **)
      def ai_odd?(**) = IsEvenAI.odd?(self, **)
      def jev_even?(**) = IsEvenAI.even?(self, **, provider: :jev)
      def jev_odd?(**) = IsEvenAI.odd?(self, **, provider: :jev)
    end

    refine Integer do
      import_methods Methods
    end

    # Floats, Rationals, BigDecimals... all require allow_non_integer: true, like everything else.
    refine Numeric do
      import_methods Methods
    end

    # Strings require allow_non_integer: true, per call or via IsEvenAI.configure.
    refine String do
      import_methods Methods
    end
  end
end
