require 'pathname'
require 'stringio'

require 'nl'

RSpec.describe Ynl do
  let(:yaml) { Pathname(__dir__) + 'fixtures/conntrack.yaml' }

  describe Ynl::Parser do
    let(:parser) do
      Ynl::Parser.new(yaml.read)
    end

    example do
      family = parser.parse

      aggregate_failures do
        expect(family.name).to eq 'conntrack'
        expect(family.protonum).to eq 12
      end
    end
  end

  describe Ynl::Family do
    example do
      cls = Ynl::Family.build(yaml)      
      binding.irb
    end
  end
end
