require "simplecov"
require "simplecov-cobertura"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter
]

SimpleCov.start "rails" do
  track_files "{app,lib}/**/*.rb"
  add_filter "db/migrate"
  add_filter "spec/"
  add_filter "vendor/"

  SimpleCov.coverage_dir "tmp/testresults/coverage"
end
