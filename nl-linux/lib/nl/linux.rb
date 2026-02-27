Dir['../../generated/nl/linux/*.rb', base: __dir__].each do |file|
  require_relative file
end
