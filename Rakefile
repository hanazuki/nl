require 'pathname'

task :spec do
  %w[nl ynl nl-linux].each do |gem|
    Dir.chdir(gem) do
      sh 'rake', 'spec'
    end
  end
end

task :default => :spec
