require 'stringio'

require_relative 'parser'
require_relative 'generator'

module Ynl
  class Family
    def self.build(path)
      require 'nl'

      defs = Ynl::Parser.parse_file(path)

      buf = StringIO.new
      classname = Generator.new(defs, buf).generate(namespace: 'self')
      classdef = buf.string

      Module.new { eval(classdef) }.const_get(classname)
    end
  end
end
