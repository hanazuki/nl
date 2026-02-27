# For each spec in linux/ directory, generate a .rb file in lib/nl/linux/ directory
FileList['linux/*.yaml'].each do |spec|
  target = spec.sub('linux/', 'lib/nl/linux/')
  task :generate => target
  task target => spec do
    require 'ynl'
    File.open(target, 'w') do |out|
      Ynl::Family.generate(spec, out, namespace: 'Nl::Linux')
    end
  end
end

task :default => :generate
