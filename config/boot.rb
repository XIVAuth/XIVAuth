ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# Disable bootsnap for the test environment
require "bootsnap/setup" unless ENV["RAILS_ENV"] == "test"
