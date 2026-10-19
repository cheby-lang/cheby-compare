#!/bin/sh
# Ruby setup for cheby-compare (langs/ruby.toml). Idempotent; it installs nothing when Homebrew's
# Ruby is already present, and it never touches the network otherwise.
#
# - Ruby 4.0 comes from Homebrew's `ruby` formula, reached at /opt/homebrew/opt/ruby/bin, which
#   langs/ruby.toml puts first on PATH (/usr/bin/ruby is macOS's Ruby 2.6, without YJIT).
# - The benchmarks use only the standard library and its default gems (json, set), so there is
#   no Gemfile, no bundler and no gem cache to prepare. This script checks that they load and
#   that YJIT is compiled in.
set -eu

RUBY_BIN=/opt/homebrew/opt/ruby/bin
RUBY="$RUBY_BIN/ruby"

if [ ! -x "$RUBY" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "brew install ruby"
    brew install ruby
  else
    echo "ruby: $RUBY is missing and Homebrew is not installed" >&2
    exit 1
  fi
fi

version=$("$RUBY" --version)
case "$version" in
  "ruby 4.0"*) echo "ruby: $version ($RUBY)" ;;
  *) echo "ruby: warning: $version, CONVENTIONS.md pins Ruby 4.0" >&2 ;;
esac

# YJIT must be available (the run command passes --yjit), and json must load.
"$RUBY" --yjit -e '
  abort "ruby: YJIT is not available in this build" unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  require "json"
  puts "  ok       yjit, json #{JSON::VERSION}"
'
