#!/usr/bin/env ruby

# This script checks git for local file changes to send to rubocop for
# style validation.
#
# Requires: git, json, rubocop
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
  # TODO : change this to use the Git class
  rubocop(`git diff --name-only master`.split(/\s+/))
end

def check_files
  g = Git.open('.')
  s = g.status
  rubocop([s.changed.keys, s.added.keys].flatten.grep(/\.rb$/))
end

def rubocop(files = [])
  return if files.empty?
  puts `rubocop #{files.join(' ')} 2>/dev/null`
end

def show_help
  puts "#{$PROGRAM_NAME}: RuboCop Your Changes"
  puts
  puts File.read(__FILE__)[/(?:^#(?:[^!].*)?\n)+/s].gsub(/^#/, ' ')
  exit
end

run
