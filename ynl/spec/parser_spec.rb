require 'pathname'
require 'ynl'

RSpec.describe Ynl::Parser do
  def parse(filename)
    path = Pathname(__dir__) + 'fixtures' + filename
    path.open {|f| Ynl::Parser.new(f) }.parse
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

      it 'has no dump request (none specified in yaml)' do
        expect(op.dumpit.request).to be_nil
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
end
