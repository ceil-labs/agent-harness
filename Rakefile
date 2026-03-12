# frozen_string_literal: true

require "rake"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.pattern = "spec/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

Rake::TestTask.new(:test_verbose) do |t|
  t.libs << "spec"
  t.pattern = "spec/**/*_test.rb"
  t.verbose = true
  t.options = "-v"  # Minitest verbose: shows each test name
end

Rake::TestTask.new(:test_interfaces) do |t|
  t.libs << "spec"
  t.pattern = "spec/interfaces/*_test.rb"
  t.verbose = true
end

task default: :test
