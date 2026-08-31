# frozen_string_literal: true

require "fileutils"

class AtomicEvidencePublisher
  class PublicationError < StandardError; end

  attr_reader :output_root, :staging_root, :backup_root

  def initialize(output_root, validator: nil)
    @output_root = File.expand_path(output_root)
    parent = File.dirname(@output_root)
    basename = File.basename(@output_root)
    @staging_root = File.join(parent, ".#{basename}-next")
    @backup_root = File.join(parent, ".#{basename}-previous")
    @validator = validator || ->(root) { raise PublicationError, "staging is empty" unless Dir.exist?(root) && !Dir.empty?(root) }
  end

  def publish(run_status:, failpoint: nil)
    recover_interrupted_swap
    FileUtils.rm_rf(staging_root)
    FileUtils.mkdir_p(staging_root)
    begin
      yield staging_root
      unless run_status == "passed"
        FileUtils.rm_rf(staging_root)
        return :retained_prior_success
      end
      @validator.call(staging_root)
      swap(failpoint)
      :published
    rescue StandardError
      FileUtils.rm_rf(staging_root) if Dir.exist?(staging_root)
      raise
    end
  end

  private

  def recover_interrupted_swap
    if Dir.exist?(backup_root) && !Dir.exist?(output_root)
      File.rename(backup_root, output_root)
    elsif Dir.exist?(backup_root) && Dir.exist?(output_root)
      FileUtils.rm_rf(backup_root)
    end
    FileUtils.rm_rf(staging_root) if Dir.exist?(staging_root)
  end

  def swap(failpoint)
    retained_previous = false
    begin
      if Dir.exist?(output_root)
        File.rename(output_root, backup_root)
        retained_previous = true
      end
      raise PublicationError, "injected swap failure before promotion" if failpoint == :before_promote
      File.rename(staging_root, output_root)
      raise PublicationError, "injected swap failure after promotion" if failpoint == :after_promote
      FileUtils.rm_rf(backup_root) if retained_previous
    rescue StandardError => error
      rollback_swap(retained_previous)
      raise PublicationError, "atomic Evidence swap failed and was rolled back: #{error.message}"
    end
  end

  def rollback_swap(retained_previous)
    if retained_previous
      FileUtils.rm_rf(output_root) if Dir.exist?(output_root)
      File.rename(backup_root, output_root) if Dir.exist?(backup_root)
    else
      FileUtils.rm_rf(output_root) if Dir.exist?(output_root)
    end
  end
end
