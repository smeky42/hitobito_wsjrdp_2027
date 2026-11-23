# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # Writes the parts still to write, in order, each in its own transaction
  # and planned again first. A new digest makes the part stale, an error
  # fails it; either stops the run. Calling again goes on, skipping what
  # depends on a failed part.
  class Apply
    class Refused < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    # Another run already wrote the part with data fetched later.
    class NewerWritten < StandardError; end

    def initialize(run, actor:, confirmed:, warnings_confirmed:, now: Time.current)
      @run = run
      @actor = actor
      @confirmed = confirmed
      @warnings_confirmed = warnings_confirmed
      @now = now
    end

    def call
      claim
      status = WsjrdpSyncRun::STOPPED
      error = nil
      begin
        Timing.record(@run, "apply") { status = write_parts }
      rescue => e # never leave the run "applying"
        error = Wsjrdp::Sync.error_text(e)
      end
      @run.update!(status: status, error_message: error, finished_at: (Time.current unless status == WsjrdpSyncRun::STOPPED),
        stats: Stats.sum(@run.parts.reload.map(&:modified_rows)).to_stats)
      @run
    end

    private

    # Takes the run for this request, or refuses.
    def claim
      @run.with_lock do
        raise Refused, :not_open unless @run.open?
        raise Refused, :not_confirmed unless @confirmed
        warnings = @run.warnings?
        raise Refused, :warnings_not_confirmed if warnings && !@warnings_confirmed

        @run.update!(status: WsjrdpSyncRun::APPLYING, confirmed_by: @actor, confirmed_at: @now,
          **(warnings ? {warnings_confirmed_by: @actor, warnings_confirmed_at: @now} : {}))
      end
    end

    # {part key => data} of every part whose files are still there.
    def data
      @run.parts.each_with_object({}) do |part, data|
        data[part.part_key] = Files.data(part.files) if part.files_purged_at.nil? && part.files.any?
      rescue Files::Missing
        nil
      end
    end

    # The run's status once every part still to write was tried.
    def write_parts
      context = Context.new(data: data, now: @now, actor: @actor)
      blocked = Set.new
      @run.parts.reload.each do |part|
        if [WsjrdpSyncRunPart::FAILED, WsjrdpSyncRunPart::SKIPPED].include?(part.status)
          blocked << part.part_key
        elsif part.writable?
          next skip(part, blocked) if part.part_class.depends_on.any? { |key| blocked.include?(key) }
          return WsjrdpSyncRun::STOPPED unless write(part, context)

          @run.touch # progress: Cancel judges a run stuck by updated_at
        end
      end
      done = @run.parts.reload.all? { |part| part.status == WsjrdpSyncRunPart::APPLIED }
      done ? WsjrdpSyncRun::APPLIED : WsjrdpSyncRun::PARTLY_APPLIED
    end

    # True when written; the state goes with the data.
    def write(part, context)
      stale = nil
      Timing.record(part, "apply") do |timing|
        ActiveRecord::Base.transaction do
          lock(part.part_key)
          raise NewerWritten, I18n.t("fin.sync.run.newer_written") if newer_written?(part)

          data = context.data_of(part.part_key) || raise(Files::Missing, "the files of the part are gone")
          handler = part.part_class.new(context)
          plan = handler.plan(data)
          if plan.digest == part.plan_digest
            stats = handler.apply(data, plan)
            part.update!(status: WsjrdpSyncRunPart::APPLIED, applied_at: Time.current, error_message: nil, stats: stats.to_stats)
          else
            stale = plan
            timing["status"] = Timing::STALE
            raise ActiveRecord::Rollback
          end
        end
      end
      return mark_stale(part, stale) if stale

      part.save! # the timing
      true
    rescue => e
      Rails.logger.error("sync part #{part.part_key} of run #{@run.id} failed: #{e.class}: #{e.message}")
      part.update!(status: WsjrdpSyncRunPart::FAILED,
        error_message: e.is_a?(NewerWritten) ? e.message : Wsjrdp::Sync.error_text(e))
      false
    end

    # One run at a time writes a part, until its transaction ends.
    def lock(part_key)
      connection = ActiveRecord::Base.connection
      connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{connection.quote(part_key)}))")
    end

    # Whether another run wrote this part with newer data.
    def newer_written?(part)
      WsjrdpSyncRunPart.where(part_key: part.part_key, status: WsjrdpSyncRunPart::APPLIED)
        .where(fetch_started_at: part.fetch_started_at..).where.not(id: part.id).exists?
    end

    def mark_stale(part, plan)
      part.update!(status: WsjrdpSyncRunPart::STALE, plan: plan.to_h, plan_digest: plan.digest, counts: plan.counts)
      false
    end

    def skip(part, blocked)
      part.update!(status: WsjrdpSyncRunPart::SKIPPED)
      blocked << part.part_key
    end
  end
end
