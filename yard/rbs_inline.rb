# YARD does not recognize the trailing ! in rbs-inline's `@rbs!` annotation,
# so it otherwise renders embedded RBS declarations as prose.
YARD::DocstringParser.after_parse do |parser|
  parser.text.gsub!(
    /^@rbs!.*(?:\n|\z)(?:(?:^[ \t]+.*|^[ \t]*)(?:\n|\z))*/,
    '',
  )
end
