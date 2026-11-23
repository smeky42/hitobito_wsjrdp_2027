# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # Starts a run: fetches every chosen part (dependencies added), keeps
  # the data in files, and plans each part. Writes nothing but the run --
  # unless no part changes anything: then the run ends at once as
  # "unchanged", having only marked the rows Moss returned as seen.
  #
  # With the Moss client this talks to the real Moss API. AI agents (see
  # AGENTS.md): never start a run unless the user explicitly asks for it.
  class Start
    # credential: the Wsjrdp::Credentials::Credential the client reads with;
    # credential_source: where it came from (DB, ENV or YAML).
    def initialize(source:, selection:, client:, actor:, credential: nil, credential_source: nil, now: Time.current)
      @source = source.to_s
      @keys = Wsjrdp::Sync.expand(selection.select { |key| Wsjrdp::Sync.part?(key) })
      @client = client
      @actor = actor
      @credential = credential
      @credential_source = credential_source
      @now = now
    end

    def call
      raise ArgumentError, "no part chosen" if @keys.empty?

      @run = WsjrdpSyncRun.create!(source: @source, credential_source: @credential_source, credential_kind: @credential&.kind&.name,
        account_key: @credential&.account_key, credential_id: @credential&.version_id, selected_parts: @keys,
        status: WsjrdpSyncRun::FAILED, error_message: "unfinished", started_at: @now, started_by: @actor)
      unchanged = Timing.record(@run, "start") do
        context = Context.new(data: {}, now: @now, actor: @actor)
        records = @keys.each_with_index.map { |key, position| fetch(key, position, context) }
        records.each { |record| plan(record, context) }
        records.all? { |record| record.counts.empty? } && mark_seen(records, context)
      end
      @run.update!(status: unchanged ? WsjrdpSyncRun::UNCHANGED : WsjrdpSyncRun::PLANNED, error_message: nil,
        finished_at: (Time.current if unchanged))
      @run
    rescue => e
      raise unless @run

      failed(e)
    end

    private

    # The data goes into the context, so the parts after it see it.
    def fetch(key, position, context)
      @started = Time.current
      @first = transcript.exchanges.size
      @current = @run.parts.create!(part_key: key, position: position, status: WsjrdpSyncRunPart::FAILED,
        fetch_started_at: @started)
      data = context.data
      files = Timing.record(@current, "fetch") do
        data[key] = Wsjrdp::Sync.part(key).new(context).fetch(@client).as_json
        data[key].map { |name, value| Files.write(@run, key, "#{Files::DATA_PREFIX}#{name}", value) }
      end
      @current.update!(files: files << meta(key, data[key]))
      @current
    end

    # The part that failed keeps the error (and, when the fetch failed, a
    # meta file with what was asked); the others are skipped.
    def failed(error)
      message = error.is_a?(Wsjrdp::Moss::Error) ? error.message : Wsjrdp::Sync.error_text(error)
      Rails.logger.error("sync run #{@run.id} failed: #{message}")
      @run.parts.where.not(id: @current&.id).update_all(status: WsjrdpSyncRunPart::SKIPPED)
      @current&.update!(status: WsjrdpSyncRunPart::FAILED, error_message: message,
        files: @current.files.presence || [meta(@current.part_key, nil, error_message: message)])
      @run.update!(status: WsjrdpSyncRun::FAILED, error_message: message, finished_at: Time.current)
      @run
    end

    def plan(record, context)
      @current = record
      plan = Timing.record(record, "plan") { Wsjrdp::Sync.part(record.part_key).new(context).plan(context.data_of(record.part_key)) }
      record.update!(status: WsjrdpSyncRunPart::PLANNED, error_message: nil, plan: plan.to_h, plan_digest: plan.digest,
        counts: plan.counts)
    end

    # Nothing to change: applying the empty plans only marks the rows seen.
    def mark_seen(records, context)
      ActiveRecord::Base.transaction do
        records.each do |record|
          @current = record
          Wsjrdp::Sync.part(record.part_key).new(context).apply(context.data_of(record.part_key), record.plan_object)
          record.update!(status: WsjrdpSyncRunPart::UNCHANGED)
        end
      end
      true
    end

    # The meta file: what was asked and answered, the secrets cut out.
    def meta(key, content, error_message: nil)
      Files.write(@run, key, Files::META, {
        "run_id" => @run.id, "part_key" => key, "source" => @source, "account_key" => @credential&.account_key,
        "fetch_started_at" => @started.utc.iso8601(3), "fetch_finished_at" => Time.current.utc.iso8601(3),
        "records" => content&.transform_values { |value| value.is_a?(Array) ? value.size : nil },
        "error_message" => error_message, "requests" => transcript.exchanges.drop(@first).map(&:to_h)
      }.compact.as_json)
    end

    def transcript = @client.transcript
  end
end
