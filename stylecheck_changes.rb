#!/usr/bin/env ruby
# frozen_string_literal: true

# This script checks git for local changes to send to lint checkers for
# style validation.
#
# Requires: git, and optionally rubocop, haml-lint, jshint, scss-lint
#
# rubocop:disable Style/GlobalVars, Metrics/MethodLength

require 'optparse'

LINTERS = {
  rb: {
    bin: 'rubocop',
    opts: '--format simple -D',
    autocorrect_opt: '-a',
    installer: 'gem install rubocop',
    ext: %w[rb rake]
  },
  js: {
    bin: 'jshint',
    installer: 'brew install node; npm install -g jshint'
  },
  haml: {
    bin: 'haml-lint',
    installer: 'gem install haml-lint'
  },
  scss: {
    bin: 'scss-lint',
    installer: 'gem install scss_lint',
    ext: %w[css scss sass less]
  }
}.freeze

MAIN_BRANCH = 'master'.freeze

GIT_INSTALLER = 'brew install git'.freeze

##########################################

$options = {}

def opt_set(opts, flags = [], description = '')
  sym = flags.last.gsub(/^--/, '').tr('-', '_').gsub(/\s.*/, '').to_sym
  opts.on(*[flags, description].flatten) { |o| $options[sym] = o }
end

def banner(opts)
  opts.banner =
    "StyleCheck Your Changes\n\n" \
    'This script checks for changes to send to linters for ' \
    "style validation.\n\n" \
    "Linters: #{LINTERS.values.map { |l| l[:bin] }.join(', ')}\n\n" \
    "Usage: #{File.basename(__FILE__)} [options]"
end

def scope_opts(opts)
  opt_set(
    opts, ['-f [TYPE]', '--file-type [TYPE]'],
    "Run lint checks on a specific file type (#{LINTERS.keys.join(', ')})"
  )

  opts.on(
    '-b [BRANCH]', '--branch [BRANCH]',
    "Check files in the current branch vs another (defaults to #{MAIN_BRANCH})"
  ) do |o|
    $options[:check_branch] = true
    $options[:vs_branch] = o || MAIN_BRANCH
  end

  opt_set(opts, ['-l', '--lines-only'], 'Only check changed lines')
end

def parse_opts
  OptionParser.new do |opts|
    banner(opts)
    opt_set(opts, ['-v', '--verbose'], 'Run verbosely')
    opt_set(opts, ['-t', '--test'], 'Test mode')
    scope_opts(opts)
    opt_set(opts, ['-a', '--auto-correct'], 'Run auto-correct if available')
    opt_set(opts, ['-i', '--run-installer'], 'Run installers for linters')
  end.parse!

  puts '[OPTS] ' + $options.inspect if $options[:verbose]
end

################################################

def git_check
  return if bin_exists?(:git)
  puts "git is not installed, please run '#{GIT_INSTALLER}'"

  if $options[:run_installer]
    puts 'Installing git...'
    puts GIT_INSTALLER
    puts `#{GIT_INSTALLER}`
  end

  exit(1)
end

def branch_files
  `git diff --name-only #{$options[:vs_branch]}`.split(/\s+/)
end

def local_files
  `git status -s`.split(/\n/).grep(/^[^D]/).map { |f| f.split(/\s/).last }
end

def bin_exists?(bin)
  `which #{bin}` != ''
end

def match_files(ext, files)
  linter = LINTERS[ext]
  exts = linter.key?(:ext) ? linter[:ext] : [ext]
  exts.map { |e| files.grep(/\.#{e}$/) }.flatten
end

def file_match(ext, files = [])
  matched_files = match_files(ext, files)
  puts "Found #{matched_files.length} #{ext} file(s)" if
    $options[:test] || $options[:verbose]

  puts matched_files.join("\n") + "\n\n" if
    !matched_files.empty? && $options[:verbose]

  matched_files
end

def handle_missing_linter(linter = {})
  if $options[:run_installer]
    puts "Running #{linter[:bin]} installer"
    puts linter[:installer]
    puts `#{linter[:installer]}`
  elsif $options[:test] || $options[:verbose]
    puts "#{linter[:bin]} not found, run '#{linter[:installer]}'\n"
  end
end

def added_file?(file)
  !`git status -s #{file}`.match(/^\?\?/).nil?
end

def parse_changed(array, l)
  return unless l =~ /^@@ -(.*?) \+(.*?) @@/
  num, steps = Regexp.last_match[2].split(/,/)
  num = num.to_i

  (0..steps.to_i).to_a.each do
    array << num
    num += 1
  end
end

def branch_lines(file)
  line_numbers = []

  `git diff -U0 #{$options[:vs_branch]} #{file} | grep "^\@\@"`
    .split(/(\r|\n)+/).each { |l| parse_changed(line_numbers, l) }

  line_numbers
end

def local_lines(file)
  `git blame #{file} | grep -n '\^0\\{8\\} ' | cut -f1 -d:`
    .split(/(\r|\n)+/).grep(/\S/).map(&:to_i)
end

def lines_hash(file)
  lines = local_lines(file)
  lines << branch_lines(file) if $options[:check_branch]
  lines.flatten.each_with_object({}) { |l, hash| hash[l] = 0 }
end

def filter_lines(file, results)
  line_results = []
  lines = lines_hash(file)

  results.split(/(\r|\n)+/).each do |l|
    if l =~ /^[C,W]:(\d+):/ # TODO: put this regex in the LINTERS hash
      num = Regexp.last_match(1).to_i
      line_results << l if lines.key?(num)
    end
  end

  line_results.unshift("== #{file} ==") unless line_results.empty?
  line_results
end

def lint_file_lines(linter, file, opts)
  cmd = "#{linter[:bin]} #{opts} #{file} 2>/dev/null"
  puts "[CMD] #{cmd}" && return if $options[:test]
  results = `#{cmd}`
  puts added_file?(file) ? results : filter_lines(file, results)
end

def lint_files(linter, opts, files)
  cmd = "#{linter[:bin]} #{opts} #{files.join(' ')} 2>/dev/null"
  puts "[CMD] #{cmd}" if $options[:test]
  puts `#{cmd}` unless files.empty? || $options[:test]
end

def run_linter(linter = {}, files = [])
  opts = linter[:opts] || ''
  opts += " #{linter[:autocorrect_opt]}" if $options[:auto_correct]

  if $options[:lines_only] # one file at a time
    files.each { |f| lint_file_lines(linter, f, opts) }
  else # run bulk command
    lint_files(linter, opts, files)
  end
end

def run_check(ext, files = [])
  linter = LINTERS[ext]

  puts "\n#{linter[:bin]}\n#{'-' * linter[:bin].length}" if
    $options[:verbose] || $options[:test]

  matched_files = file_match(ext, files)

  if bin_exists?(linter[:bin])
    run_linter(linter, matched_files)
  else
    handle_missing_linter(linter)
  end
end

def run_checks
  files = local_files
  files << branch_files if $options[:check_branch]

  LINTERS.keys.each do |ext|
    next if $options[:file_type] && $options[:file_type] != ext.to_s
    run_check(ext, files.flatten.uniq)
  end
end

def run
  parse_opts
  git_check
  run_checks
end

run
