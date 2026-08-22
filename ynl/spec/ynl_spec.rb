require 'pathname'
require 'stringio'

require 'nl'

RSpec.describe Ynl do
  let(:yaml) { Pathname(__dir__) + 'fixtures/conntrack.yaml' }

  describe Ynl::Parser do
    let(:parser) do
      yaml.open {|f| Ynl::Parser.new(f) }
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

      expect(cls.name).to match /::Conntrack\z/
      expect(cls::NAME).to eq 'conntrack'
      expect(cls::PROTOCOL).to be_kind_of Nl::Protocols::Raw
    end

    it 'generates a dump method for an operation with an implicit empty request' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/ops_unified.yaml')

      expect(cls.instance_methods(false)).to include(:dump_op_a)
      expect(cls::Messages::DumpOpARequest::TYPE).to eq 1
      expect(cls::Messages::DumpOpARequest::ATTRIBUTES).to be_empty
    end

    it 'documents operation permission flags' do
      generated = StringIO.new
      path = Pathname(__dir__) + 'fixtures/operation_flags.yaml'
      path.open { |source| Ynl::Family.generate(source, generated) }

      expect(generated.string).to match(
        /# Change a global network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires CAP_NET_ADMIN in the initial user namespace\./,
      )
      expect(generated.string).to match(
        /# Change a namespaced network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires CAP_NET_ADMIN in the user namespace owning the network namespace\./,
      )
      expect(generated.string).not_to match(/# Read a network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires/)
    end
  end
end
