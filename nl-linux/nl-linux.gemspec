require_relative 'lib/nl/linux/version'

Gem::Specification.new do |spec|
  spec.name = 'nl-linux'
  spec.version = Nl::Linux::VERSION
  spec.authors = ['Kasumi Hanazuki']
  spec.email = ['kasumi@rollingapple.net']

  spec.summary = 'Clients for Linux kernel Netlink API'
  spec.description = "nl-linux is a collection of Netlink clients for Linux kernel APIs, generated from the kernel's YAML specifications (YNL)."
  spec.homepage = 'https://github.com/hanazuki/nl'
  spec.license = '(GPL-2.0 WITH Linux-syscall-note) OR BSD-3-Clause'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "https://github.com/hanazuki/nl/tree/v#{Nl::Linux::VERSION}"
  spec.metadata['changelog_uri'] = 'https://github.com/hanazuki/nl/blob/master/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines(?\x0, chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  # Generated files
  spec.files << 'generated/nl/linux.rb'
  generated = spec.files.filter_map { "generated/nl/linux/#{$~[:name].gsub(?-, ?_)}.rb" if %r[\Alinux/(?<name>[^/]+)\.yaml\z] =~ it }
  spec.files.concat(generated)
  spec.files.concat Dir['sig/**/*.rbs']

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib', 'generated']

  spec.add_dependency 'nl', Nl::Linux::VERSION
  spec.add_development_dependency 'ynl', Nl::Linux::VERSION
end
