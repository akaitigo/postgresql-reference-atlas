# frozen_string_literal: true

require "json"
require_relative "security_failure_diagnostics"

module SecurityJsonOutput
  STDIO_LIMIT = 2048
  JSON_CANDIDATE_LIMIT = 5

  module_function

  def bounded_text(text, limit: STDIO_LIMIT)
    value = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    return value if value.bytesize <= limit

    value.byteslice(0, limit) + "...(truncated)"
  end

  def json_candidate_lines(stdout)
    stdout.to_s.lines.map(&:strip).reject(&:empty?).select do |line|
      line.start_with?("{", "[")
    end
  end

  def parse_single_json_object!(stdout:, stderr:, marker:, command:, exit_status:, failed_row:, target:, phase:)
    candidates = json_candidate_lines(stdout)
    object_candidates = candidates.select do |line|
      (line.start_with?("{") && line.end_with?("}")) || (line.start_with?("[") && line.end_with?("]"))
    end
    marker_present = stdout.include?(marker) || stderr.include?(marker)

    if object_candidates.empty?
      raise structured_failure(
        failed_row: failed_row,
        target: target,
        phase: phase,
        reason: candidates.empty? ? (marker_present ? "marker-only" : "missing-json") : "truncated-json",
        command: command,
        exit_status: exit_status,
        stdout: stdout,
        stderr: stderr,
        marker_present: marker_present,
        json_candidate_lines: candidates
      )
    end

    if object_candidates.length > 1
      raise structured_failure(
        failed_row: failed_row,
        target: target,
        phase: phase,
        reason: "multiple-json",
        command: command,
        exit_status: exit_status,
        stdout: stdout,
        stderr: stderr,
        marker_present: marker_present,
        json_candidate_lines: object_candidates
      )
    end

    parsed = JSON.parse(object_candidates.first)
    unless parsed.is_a?(Hash)
      raise structured_failure(
        failed_row: failed_row,
        target: target,
        phase: phase,
        reason: "non-object-json",
        command: command,
        exit_status: exit_status,
        stdout: stdout,
        stderr: stderr,
        marker_present: marker_present,
        json_candidate_lines: object_candidates
      )
    end

    parsed
  rescue JSON::ParserError => error
    raise structured_failure(
      failed_row: failed_row,
      target: target,
      phase: phase,
      reason: "truncated-json",
      command: command,
      exit_status: exit_status,
      stdout: stdout,
      stderr: stderr,
      marker_present: marker_present,
      json_candidate_lines: object_candidates.empty? ? candidates : object_candidates,
      parse_error: "#{error.class}: #{error.message}"
    )
  end

  def command_failure_result(phase:, command:, exit_status:, stdout:, stderr:, marker_present: nil, reason: nil, json_candidate_lines: [], parse_error: nil)
    {
      "phase"=>phase,
      "reason"=>reason,
      "command_failure"=>{
        "command"=>Array(command).join(" "),
        "exit_status"=>exit_status,
        "stdout"=>bounded_text(stdout),
        "stderr"=>bounded_text(stderr)
      },
      "marker_present"=>marker_present,
      "json_candidate_lines"=>Array(json_candidate_lines).first(JSON_CANDIDATE_LIMIT).map { |line| bounded_text(line, limit: 256) },
      "json_candidate_count"=>Array(json_candidate_lines).length,
      "parse_error"=>parse_error
    }.compact
  end

  def structured_failure(failed_row:, target:, phase:, reason:, command:, exit_status:, stdout:, stderr:, marker_present:, json_candidate_lines:, parse_error: nil)
    SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: failed_row,
      target: target,
      oracle_error: "#{target} runtime #{phase} failed: #{reason}",
      actual_result: command_failure_result(
        phase: phase,
        reason: reason,
        command: command,
        exit_status: exit_status,
        stdout: stdout,
        stderr: stderr,
        marker_present: marker_present,
        json_candidate_lines: json_candidate_lines,
        parse_error: parse_error
      ).merge("marker_present"=>marker_present),
      oracle_predicates: {
        "json_object_present"=>reason.nil?,
        "marker_present"=>marker_present,
        "json_candidate_count_exactly_one"=>Array(json_candidate_lines).length == 1
      }
    )
  end
end
