directory 'generated'
directory 'generated/nl' => 'generated'
directory 'generated/nl/linux' => 'generated/nl'

# For each of linux/%.yaml spec, generate generated/nl/linux/%.rb
FileList['linux/*.yaml'].each do |spec|
  target = 'generated/nl/' + spec.gsub(?-, ?_).sub('.yaml', '.rb')
  task :generate => target
  task target => [spec, 'generated/nl/linux'] do
    require 'ynl'
    File.open(target, 'w') do |out|
      Ynl::Family.generate(spec, out, namespace: 'Nl::Linux')
    end
  end
end

task :default => :generate
