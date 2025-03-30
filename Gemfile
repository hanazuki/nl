source 'https://rubygems.org'

Dir['*/*.gemspec', base: __dir__].each do |gemspec|
  gemspec path: File.dirname(gemspec), name: File.basename(gemspec, '.gemspec')
end

gem 'rake', '~> 13.0'
gem 'rspec', '~> 3.0'
