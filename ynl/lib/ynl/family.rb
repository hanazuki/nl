require 'stringio'

require_relative 'parser'
require_relative 'generator'

module Ynl
  class Family
    # Builds a Ruby class from a spec file
    def self.build(path)
      buf = StringIO.new(Generator::PRELUDE.dup)
      classname = File.open(path) {|f| generate(f, buf, namespace: 'self') }

      Module.new { eval(buf.string) }.const_get(classname)
    end

    # Generates Ruby code from a spec source
    def self.generate(source, out, **kwargs)
      Generator.new(Ynl::Parser.new(source).parse, out).generate(**kwargs)
    end
  end
end
