require_relative '../nl/lib/nl/version'

Gem::Specification.new do |spec|
  spec.name = 'ynl'
  spec.version = Nl::VERSION
  spec.authors = ['Kasumi Hanazuki']
  spec.email = ['kasumi@rollingapple.net']

  spec.summary = 'Linux Netlink - core'
  spec.description = 'Linux Netlink'
  spec.homepage = 'https://github.com/hanazuki/nl'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "https://github.com/hanazuki/nl"
  spec.metadata['changelog_uri'] = 'https://github.com/hanazuki/nl/blob/master/ynl/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines(?\x0, chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nl', Nl::VERSION

  spec.add_dependency 'yaml'
end
