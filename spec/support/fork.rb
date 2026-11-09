# Run tagged examples in a child process while reporting their results in the
# parent. RSpec catches assertion failures, so exit status alone is insufficient.
module ForkedExamples
  def self.run(example)
    reader, writer = IO.pipe
    pid = Process.fork do
      reader.close
      begin
        example.run
        result = example.execution_result
        Marshal.dump({
          exception: example.exception,
          pending: example.metadata[:pending],
          skip: example.metadata[:skip],
          pending_message: result.pending_message,
          pending_exception: result.pending_exception,
          pending_fixed: result.pending_fixed,
        }, writer)
        writer.close
        Process.exit!(0)
      rescue Exception => error
        warn "Forked example: #{error.full_message}"
        Process.exit!(1)
      end
    end
    writer.close

    begin
      outcome = Marshal.load(reader)
    rescue EOFError
      outcome = nil
    ensure
      reader.close
      _, status = Process.wait2(pid)
    end
    unless status.success? && outcome
      raise "Forked example exited without a result: #{status.inspect}"
    end

    # Procsy's execution flag was changed only in the child; restore it along
    # with the example's outcome before RSpec finishes reporting in the parent.
    example.instance_variable_set(:@executed, true)
    example.metadata[:pending] = outcome[:pending]
    example.metadata[:skip] = outcome[:skip]
    result = example.execution_result
    result.pending_message = outcome[:pending_message]
    result.pending_exception = outcome[:pending_exception]
    result.pending_fixed = outcome[:pending_fixed]
    example.example.display_exception = outcome[:exception] if outcome[:exception]
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(fork: true) do |metadata|
    metadata[:skip] ||= 'Process.fork is unavailable' unless Process.respond_to?(:fork)
  end

  config.around(:example, fork: true) do |example|
    ForkedExamples.run(example)
  end
end
