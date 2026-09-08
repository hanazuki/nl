require 'stringio'

require_relative 'parser'
require_relative 'generator'

module Ynl
  # Entry points for generating family classes from YNL specifications.
  class Family
    # Builds a family class from a YNL specification file.
    #
    # @param [String, #to_path] path a path to a YNL specification file
    # @return [Class<Nl::Family>] the generated family class
    # @rbs (String | _PathLike path) -> Class
    def self.build(path)
      buf = StringIO.new(Generator::PRELUDE.dup)
      classname = File.open(path) {|f| generate(f, buf, namespace: 'self') }

      Module.new { eval(buf.string) }.const_get(classname)
    end

    # Generates Ruby source code to define a family class from a YNL specification.
    #
    # @param [String, #read] source a YAML string or readable IO containing the YNL specification
    # @param [#write] out the destination for the generated source code
    # @option kwargs [String, nil] superclass the name of the generated class's superclass
    # @option kwargs [String, nil] namespace the namespace in which to define the family class
    # @option kwargs [String, nil] default_resolver the expression used as the default family resolver
    # @return [String] the generated family class name
    # @rbs (String | _Readable source, _Writable out, ?superclass: String?, ?namespace: String?, ?default_resolver: String?) -> String
    def self.generate(source, out, **kwargs)
      Generator.new(Ynl::Parser.new(source).parse, out).generate(**kwargs)
    end
  end
end
