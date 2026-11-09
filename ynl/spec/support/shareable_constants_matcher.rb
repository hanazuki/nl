RSpec::Matchers.define :have_shareable_constants do
  match do |family|
    @unshareable_constants = []
    pending = [family]
    visited = {}
    until pending.empty?
      namespace = pending.pop
      next if visited[namespace]
      visited[namespace] = true
      namespace.constants(false).each do |name|
        value = namespace.const_get(name, false)
        @unshareable_constants << "#{namespace}::#{name}" unless Ractor.shareable?(value)
        pending << value if value.is_a?(Module)
      end
    end
    @unshareable_constants.empty?
  end

  failure_message do
    "expected all constants to be Ractor-shareable, but these were not: #{@unshareable_constants.join(', ')}"
  end
end
