# frozen_string_literal: true

require "json"

module CanonicalJSON
  module_function

  def pretty(value, depth = 0)
    indent = "  " * depth
    child_indent = "  " * (depth + 1)
    case value
    when Hash
      return "{}" if value.empty?

      body = value.map do |key, child|
        abort "Canonical JSON object keyはStringでなければなりません" unless key.is_a?(String)

        "#{child_indent}#{string(key)}: #{pretty(child, depth + 1)}"
      end.join(",\n")
      "{\n#{body}\n#{indent}}"
    when Array
      return "[]" if value.empty?

      body = value.map { |child| "#{child_indent}#{pretty(child, depth + 1)}" }.join(",\n")
      "[\n#{body}\n#{indent}]"
    when String
      string(value)
    when Integer
      value.to_s
    when Float
      abort "Canonical JSONで非有限Floatは禁止です" unless value.finite?

      JSON.generate(value)
    when TrueClass
      "true"
    when FalseClass
      "false"
    when NilClass
      "null"
    else
      abort "Canonical JSONで未対応の型です: #{value.class}"
    end
  end

  def string(value)
    encoded = value.each_codepoint.map do |codepoint|
      case codepoint
      when 0x22 then '\\"'
      when 0x5c then "\\\\"
      when 0x08 then "\\b"
      when 0x0c then "\\f"
      when 0x0a then "\\n"
      when 0x0d then "\\r"
      when 0x09 then "\\t"
      when 0x00..0x1f, 0x2028, 0x2029 then format("\\u%04x", codepoint)
      else codepoint.chr(Encoding::UTF_8)
      end
    end.join
    %Q{"#{encoded}"}
  end
end
