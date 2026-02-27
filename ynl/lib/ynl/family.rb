require 'stringio'

require_relative 'parser'
require_relative 'generator'

module Ynl
  class Family
    # Builds a Ruby class from a spec file
    def self.build(path)
      buf = StringIO.new
      classname = generate(path, buf, namespace: 'self')
      code = buf.string

      Module.new { eval(code) }.const_get(classname)
    end

    # Generates Ruby code from a spec file
    def self.generate(path, out, **kwargs)
      out << Generator::PRELUDE
      Generator.new(Ynl::Parser.parse_file(path), out).generate(**kwargs)
    end
  end
end
