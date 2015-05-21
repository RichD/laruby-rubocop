#!/usr/bin/env ruby

# This script checks git for local file changes to send to lint checkers for
# style validation.
#
# Requires: git, json, rubocop, haml-lint, jslint, scss-lint
#
# Options:
#
#   --help     display help info
#   --branch   check current branch vs master

require 'git'
require 'rubocop'

def run
  if ARGV.empty?
    check_files
  elsif ['-h', '--help'].include?(ARGV[0])
    show_help
  elsif ['-b', '--branch'].include?(ARGV[0])
    check_branch
  end
end

def check_branch
  run_checks(`git diff --name-only master`.split(/\s+/))
end

def check_files
  g = Git.open('.')
  s = g.status
  run_checks([s.changed.keys, s.added.keys].flatten)
end

def run_checks(files = [])
  rubocop(files)
  haml_lint(files)
  js_lint(files)
  scss_lint(files)
end

def rubocop(files = [])
  puts 'Skipping rubocop...' && return if `which rubocop`.blank?
  ruby_files = files.grep(/\.rb$/)
  return if ruby_files.empty?
  puts `rubocop #{ruby_files.join(' ')} --format simple 2>/dev/null`
end

def haml_lint(files = [])
  puts 'Skipping haml-lint...' && return if `which haml-lint`.blank?
  haml_files = files.grep(/\.haml$/)
  return if haml_files.empty?
  puts `haml-lint #{haml_files.join(' ')}`
end

def js_lint(files = [])
  puts 'Skipping jslint...' && return if `which jslint`.blank?
  files.grep(/\.js$/).each do |file|
    puts "=== #{file} ==="
    puts `jslint #{file}`
  end
end

def scss_lint(files = [])
  puts 'Skipping scss-lint...' && return if `which scss-lint`.blank?
  scss_files = files.grep(/\.scss$/)
  return if scss_files.empty?
  puts `scss-lint #{scss_files.join(' ')}`
end

def show_help
  puts "#{$PROGRAM_NAME}: RuboCop Your Changes"
  puts
  puts File.read(__FILE__)[/(?:^#(?:[^!].*)?\n)+/s].gsub(/^#/, ' ')
  exit
end

run
