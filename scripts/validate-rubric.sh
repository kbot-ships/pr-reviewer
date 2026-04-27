#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <rubric.yml>" >&2
  exit 2
fi

RUBRIC_PATH="$1"

if [[ ! -f "$RUBRIC_PATH" ]]; then
  echo "pr-reviewer: rubric file not found: $RUBRIC_PATH" >&2
  exit 2
fi

ruby - "$RUBRIC_PATH" <<'RUBY'
require "psych"

path = ARGV[0]

begin
  rubric = Psych.load_file(path)
rescue Psych::SyntaxError => e
  warn "pr-reviewer: invalid YAML in #{path}: #{e.message.lines.first.strip}"
  warn "pr-reviewer: see docs/rubric-schema.md for the supported rubric shape"
  exit 2
end

unless rubric.is_a?(Hash)
  warn "pr-reviewer: rubric must be a YAML mapping at the top level (got #{rubric.class})"
  warn "pr-reviewer: see docs/rubric-schema.md for the supported rubric shape"
  exit 2
end

schema = {
  "persona" => String,
  "priorities" => Array,
  "ignore" => Array,
  "conventions" => Array,
  "notes" => String,
}

errors = []
warnings = []

rubric.each do |key, value|
  key_s = key.to_s
  if schema.key?(key_s)
    expected = schema[key_s]
    unless value.is_a?(expected)
      errors << "#{key_s} must be a #{expected} (got #{value.class})"
      next
    end

    if expected == Array
      bad_index = value.find_index do |item|
        case key_s
        when "priorities"
          if item.is_a?(String)
            false
          elsif item.is_a?(Hash)
            item.length != 1 || !item.keys.first.is_a?(String) || !item.values.first.is_a?(String)
          else
            true
          end
        else
          !item.is_a?(String)
        end
      end
      if bad_index
        if key_s == "priorities"
          errors << "#{key_s}[#{bad_index}] must be a String or single-entry mapping of String -> String (got #{value[bad_index].class})"
        else
          errors << "#{key_s}[#{bad_index}] must be a String (got #{value[bad_index].class})"
        end
      end
    end
  else
    warnings << "unknown top-level key '#{key_s}' will be passed through as reviewer guidance"
  end
end

if errors.any?
  warn "pr-reviewer: invalid rubric at #{path}"
  errors.each { |msg| warn "  - #{msg}" }
  warn "pr-reviewer: see docs/rubric-schema.md for the supported rubric shape"
  exit 2
end

warnings.each { |msg| warn "pr-reviewer: warning: #{msg}" }
puts "pr-reviewer: rubric validation passed for #{path}"
RUBY
