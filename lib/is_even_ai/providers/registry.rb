# frozen_string_literal: true

module IsEvenAI
  module Providers
    # Provider lookup. Third parties can register their own subclass of Providers::Base:
    #   IsEvenAI::Providers::Registry.register(:my_provider, MyProvider)
    module Registry
      @providers = {}

      class << self
        def register(name, klass)
          @providers[name.to_sym] = klass
        end

        def fetch(name)
          @providers.fetch(name.to_sym) do
            raise ConfigurationError, "Unknown provider #{name.inspect}; expected one of #{names.join(", ")}"
          end
        end

        def known?(name)
          @providers.key?(name.to_sym)
        end

        def names
          @providers.keys
        end

        def build(config)
          fetch(config.resolved_provider).new(config)
        end
      end
    end
  end
end
