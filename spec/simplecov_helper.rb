require "simplecov"
require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter
]

SimpleCov.start "rails" do
  cover "{app,lib}/**/*.rb"
  skip %w[db/migrate spec/ vendor/]

  SimpleCov.coverage_dir "tmp/testresults/coverage"
end
