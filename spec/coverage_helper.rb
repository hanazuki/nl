# frozen_string_literal: true

module CoverageHelper
  ROOT = File.expand_path('..', __dir__)

  def self.start(command_name)
    return unless ENV['COVERAGE']

    require 'simplecov'

    SimpleCov.command_name command_name
    SimpleCov.root ROOT
    SimpleCov.start do
      enable_coverage :branch

      cover '{nl,ynl,nl-linux}/lib/**/*.rb', 'nl-linux/generated/**/*.rb'

      skip %r{/spec/}

      group 'nl', %r{/nl/lib/}
      group 'ynl', %r{/ynl/lib/}
      group 'nl-linux', %r{/nl-linux/lib/}
      group 'Generated clients', %r{/nl-linux/generated/}
    end
  end
end
