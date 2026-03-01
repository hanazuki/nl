require 'rspec/core/rake_task'

desc 'Run tests'
task :spec

%w[nl ynl nl-linux].each do |gem|
  task "spec:#{gem}" do
    sh 'rake', '-C', gem, 'spec'
  end
  task :spec => "spec:#{gem}"
end

task :generate do
  sh 'rake', '-C', 'nl-linux', 'generate'
end

RSpec::Core::RakeTask.new(:'spec:integration') do |t|
end

task 'spec:integration' => 'generate'
task :spec => 'spec:integration'

task :default => :spec
