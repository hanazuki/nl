require 'rspec/core/rake_task'

desc 'Run tests'
task :spec

%w[nl ynl nl-linux].each do |gem|
  task "spec:#{gem}" do
    Dir.chdir(gem) do
      sh 'rake', 'spec'
    end
  end
  task :spec => "spec:#{gem}"
end

RSpec::Core::RakeTask.new(:'spec:integration') do |t|
end

task :spec => 'spec:integration'

task :default => :spec
