GEM_ROOT = File.expand_path('../..', __dir__)

directory "#{GEM_ROOT}/generated"
directory "#{GEM_ROOT}/generated/nl" => "#{GEM_ROOT}/generated"
directory "#{GEM_ROOT}/generated/nl/linux" => "#{GEM_ROOT}/generated/nl"

# For each of linux/%.yaml spec, generate generated/nl/linux/%.rb
Dir['linux/*.yaml', base: GEM_ROOT].each do |spec|
  spec_abs = File.join(GEM_ROOT, spec)
  target = "#{GEM_ROOT}/generated/nl/" + spec.gsub(?-, ?_).sub('.yaml', '.rb')
  task :generate => target
  task target => [spec_abs, "#{GEM_ROOT}/generated/nl/linux"] do
    require 'ynl'
    File.open(spec_abs, 'r') do |src|
      front = src.readlines.take_while {|l| !l.start_with?('---') }.grep(/\A\#/).join

      src.rewind

      File.open(target, 'w') do |out|
        out << front
        out << "#--\n"
        Ynl::Family.generate(src, out, namespace: 'Nl::Linux')
      end
    end
  end
end

task :default => :generate
