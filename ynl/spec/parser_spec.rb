require 'pathname'
require 'ynl'

RSpec.describe Ynl::Parser do
  def parse(filename)
    path = Pathname(__dir__) + 'fixtures' + filename
    path.open {|f| Ynl::Parser.new(f) }.parse
  end

  describe 'attribute values' do
    subject(:attributes) { parse('attribute_values.yaml').attribute_sets.fetch('attrs').attributes }

    it 'reserves values for unused attributes' do
      expect(attributes.map { [_1.name, _1.value] }).to eq([
        ['first', 1],
        ['third', 3],
        ['after-explicit-unused', 11],
      ])
    end
  end

  describe 'nest-type-value attributes' do
    subject(:type) { parse('nest_type_value.yaml').attribute_sets.fetch('outer').attributes.first.type }

    it 'preserves the type-value nesting levels' do
      expect(type).to be_a Ynl::Types::NestTypeValue
      expect(type.type_values).to eq %w[policy-id attribute-id]
      expect(type.attribute_set.name).to eq 'policy'
    end

    it 'describes every type-value level in RBS' do
      expect(type.rbs_type).to eq(
        '::Hash[::Integer, ::Hash[::Integer, AttributeSets::Policy]]',
      )
    end
  end

  describe 'RBS types' do
    it 'types binary payloads as strings' do
      expect(Ynl::Types::Binary.new.rbs_type).to eq('::String')
    end

    it 'types opaque sub-message payloads as strings' do
      expect(Ynl::Types::SubMessage.new.rbs_type).to eq('::String')
    end

    it 'preserves an indexed array element type' do
      type = Ynl::Types::IndexedArray.new(Ynl::Types::Scalar.new(type: 'u32', byte_order: :host))

      expect(type.rbs_type).to eq('::Array[::Integer]')
    end
  end

  describe 'unified enum model' do
    subject(:family) { parse('ops_unified.yaml') }

    let(:ops) { family.operations }

    # op-a is the first operation: counter advances from 0 to 1
    describe 'op-a (first do+dump operation)' do
      subject(:op) { ops.fetch('op-a') }

      it 'assigns request value 1' do
        expect(op.doit.request.value).to eq 1
      end

      it 'assigns reply value 1 (same as request in unified)' do
        expect(op.doit.reply.value).to eq 1
      end

      it 'assigns dump reply value 1' do
        expect(op.dumpit.reply.value).to eq 1
      end

      it 'assigns an empty dump request when none is specified in yaml' do
        expect(op.dumpit.request.value).to eq 1
        expect(op.dumpit.request.attributes).to be_empty
      end
    end

    # op-b-ntf: notify, counter advances from 1 to 2
    describe 'op-b-ntf (notify, auto-incremented ID)' do
      subject(:op) { ops.fetch('op-b-ntf') }

      it 'has no doit or dumpit' do
        expect(op.doit).to be_nil
        expect(op.dumpit).to be_nil
      end
    end

    # op-d: do operation after notify, counter continues from 5 → 6
    describe 'op-d (do operation after explicit-value notify)' do
      subject(:op) { ops.fetch('op-d') }

      it 'assigns request value 6' do
        expect(op.doit.request.value).to eq 6
      end

      it 'assigns reply value 6' do
        expect(op.doit.reply.value).to eq 6
      end
    end
  end

  describe 'directional enum model' do
    subject(:family) { parse('ops_directional.yaml') }

    let(:ops) { family.operations }

    # setter: do with explicit request value 10, no reply
    describe 'setter (explicit request value, no reply)' do
      subject(:op) { ops.fetch('setter') }

      it 'assigns request value 10' do
        expect(op.doit.request.value).to eq 10
      end

      it 'has no reply' do
        expect(op.doit.reply).to be_nil
      end
    end

    # getter: explicit request value 11; reply gets resp_counter=9
    # (resp_counter was 1 before ntf, ntf set it to 8 and incremented to 9)
    describe 'getter (explicit request value 11; resp_counter picks up at 9)' do
      subject(:op) { ops.fetch('getter') }

      it 'assigns request value 11' do
        expect(op.doit.request.value).to eq 11
      end

      it 'assigns reply value 9 (resp_counter after ntf)' do
        expect(op.doit.reply.value).to eq 9
      end

      it 'assigns the do request value to an implicit empty dump request' do
        expect(op.dumpit.request.value).to eq 11
        expect(op.dumpit.request.attributes).to be_empty
      end
    end

    # auto-getter: no explicit values; req_counter=12, resp_counter=10
    describe 'auto-getter (no explicit values; req_counter=12, resp_counter=10)' do
      subject(:op) { ops.fetch('auto-getter') }

      it 'assigns request value 12' do
        expect(op.doit.request.value).to eq 12
      end

      it 'assigns reply value 10' do
        expect(op.doit.reply.value).to eq 10
      end
    end

    # no-reply-setter: no explicit values, no reply — resp_counter must NOT advance
    describe 'no-reply-setter (no reply; resp_counter pauses)' do
      subject(:op) { ops.fetch('no-reply-setter') }

      it 'assigns request value 13' do
        expect(op.doit.request.value).to eq 13
      end

      it 'has no reply' do
        expect(op.doit.reply).to be_nil
      end
    end

    # after-no-reply: resp_counter should still be 11 (paused at no-reply-setter)
    describe 'after-no-reply (resp_counter resumed from paused value 11)' do
      subject(:op) { ops.fetch('after-no-reply') }

      it 'assigns request value 14' do
        expect(op.doit.request.value).to eq 14
      end

      it 'assigns reply value 11 (resp_counter did not advance for no-reply-setter)' do
        expect(op.doit.reply.value).to eq 11
      end
    end
  end

  describe 'operation flags' do
    subject(:operations) { parse('operation_flags.yaml').operations }

    it 'preserves flags as operation metadata' do
      expect(operations.fetch('global-admin').flags).to eq ['admin-perm']
      expect(operations.fetch('namespace-admin').flags).to eq ['uns-admin-perm']
    end

    it 'defaults to an empty list' do
      expect(operations.fetch('unprivileged').flags).to be_empty
    end
  end

  describe 'notifications' do
    subject(:family) { parse('notifications.yaml') }

    it 'parses and resolves multicast groups' do
      expect(family.mcast_groups.fetch('changes')).to have_attributes(
        name: 'changes',
        value: nil,
        doc: 'Object lifecycle changes.',
      )
      expect(family.mcast_groups.fetch('fixed-id').value).to eq 42
    end

    it 'parses notify operations and resolves their source operation and group' do
      notification = family.operations.fetch('object-changed').notification

      expect(notification.kind).to eq :notify
      expect(notification.message.value).to eq 2
      expect(notification.message.attributes).to be_empty
      expect(notification.source).to equal family.operations.fetch('object-get')
      expect(notification.group).to equal family.mcast_groups.fetch('changes')
    end

    it 'parses event operations with their inline message schema' do
      notification = family.operations.fetch('object-failed').notification

      expect(notification.kind).to eq :event
      expect(notification.message.value).to eq 3
      expect(notification.message.attributes).to eq %w[item-id reason]
      expect(notification.source).to be_nil
      expect(notification.group).to equal family.mcast_groups.fetch('changes')
    end

    it 'allows notifications without an explicit multicast group' do
      notification = family.operations.fetch('ungrouped-event').notification

      expect(notification.group).to be_nil
    end
  end
end
