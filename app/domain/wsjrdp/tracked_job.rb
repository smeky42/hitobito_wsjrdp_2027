# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A job in the background whose runs are tracked: each run is one
# HitobitoLogEntry kept up to date while it works, which a progress display
# (shared/wsjrdp/_tracked_job_progress) reads, and which can be cancelled
# (the controller side: Wsjrdp::TrackedJobEndpoints). Not tied to any kind of
# work -- doc/wsjrdp/tracked_jobs.md explains how to write one.
#
# A subclass names
# - log_category (a HitobitoLogEntry category; the wagon registers it) and
#   sub_category (payload sub_category, telling its runs from others of the
#   category);
# - queue_name (the Delayed::Job queue) and lock_key (a PostgreSQL advisory lock);
# - i18n_scope: its texts (log_queued, log_started, log_running, log_message,
#   log_cancelled, log_skipped, log_dequeued, log_failed; progress.* falls
#   back to wsjrdp.tracked_job.progress.*);
# - figures, the counters of its progress in display order, and pace, the
#   one the rest is estimated by; work_phase, the phase it works in;
# and does its work in #prepare (the items and the totals by figure), #work
# (ticking the progress), #empty_result and optionally #finish.
#
# A run's log entry is written as the run is queued (status queued, with the
# id of its Delayed::Job), taken over as it starts and kept up to date every
# second (Progress): its payload says the status (running, finished, failed,
# cancelled), the phase (scan, then work_phase), the totals and how many of
# them are done, the counts so far and the timing (Timing). At the end it
# gets the result and the duration.
#
# A queued entry whose job is gone was never taken over: the worker threw the
# job away before it ran -- typically a worker whose code does not know the
# class (Delayed::DeserializationError) -- and .status says so (lost).
#
# Cancelling (.cancel!) marks the running entry (cancel_requested_at,
# cancel_requested_by); the job sees the mark when it next writes its
# progress and stops after the item at hand (status cancelled). A run still
# in the queue is simply taken out of it. The job and .cancel! read and write
# the entry under a row lock, so neither overwrites the other.
#
# While it works a run holds a session-level PostgreSQL advisory lock
# (lock_key): it runs at most once at a time, and .status tells a run that
# works from one that died -- the lock ends with the database session of the
# process -- without anything written.
class Wsjrdp::TrackedJob < ::BaseJob
  class_attribute :log_category, :sub_category, :queue_name, :lock_key, :i18n_scope, :work_phase
  # The counters of the progress, in the order the display shows them; the
  # rest is estimated by the pace of `pace`.
  class_attribute :figures, default: %w[files]
  class_attribute :pace, default: "files"

  self.parameters = [:actor_id, :enqueued_at, :entry_id, :locale]

  # The times of one run: its phases measured with a monotonic clock, start
  # and end as wall-clock times.
  class Timing
    attr_reader :started_at, :finished_at, :phases

    def initialize(enqueued_at: nil)
      @enqueued_at = enqueued_at && Time.zone.parse(enqueued_at.to_s)
      @started_at = Time.current
      @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @phases = {}
    end

    # Runs the block as the named phase and answers its value.
    def measure(phase)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      @phases[phase] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(3)
    end

    def finish
      @finished_at = Time.current
      @duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start).round(3)
      self
    end

    def duration = @duration || (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start).round(3)

    def to_h
      {"enqueued_at" => @enqueued_at&.iso8601, "started_at" => @started_at.iso8601,
       "finished_at" => @finished_at&.iso8601,
       "waited_seconds" => @enqueued_at && (@started_at - @enqueued_at).round(1),
       "duration_seconds" => duration,
       "phase_seconds" => @phases.transform_keys(&:to_s)}.compact
    end
  end

  # Keeps a run's log entry up to date while it works: the totals and how
  # many of them are done, written at most once per INTERVAL.
  class Progress
    INTERVAL = 1.0

    attr_reader :totals

    def initialize(entry, totals, timing, job_class)
      @entry = entry
      @timing = timing
      @job_class = job_class
      @totals = totals.transform_keys(&:to_s)
      @done = @totals.keys.index_with(0)
      @work_started_at = Time.current
      @written_at = nil
    end

    def done = @done.dup

    # Counts what is done (counter => how many more) and writes the progress
    # once per INTERVAL; :stop when the run is to be cancelled.
    def tick(result, **counts)
      counts.each { |name, count| @done[name.to_s] = @done.fetch(name.to_s, 0) + count }
      return unless @written_at.nil? || monotonic - @written_at >= INTERVAL

      write(result) ? :stop : nil
    end

    # Writes the progress, keeping a cancel mark; true when there is one.
    def write(result)
      @written_at = monotonic
      first = @job_class.figures.first
      @job_class.with_locked_entry(@entry) do |entry, current|
        @cancel = current.slice("cancel_requested_at", "cancel_requested_by")
        entry.update_columns(
          message: I18n.t("#{@job_class.i18n_scope}.log_running", done: @done[first], total: @totals[first]),
          payload: payload(result, "running").merge(@cancel), updated_at: Time.current
        )
      end
      cancel_requested?
    end

    def cancel_requested? = @cancel.present?

    def cancel = @cancel || {}

    def payload(result, status)
      {"sub_category" => @job_class.sub_category, "status" => status, "phase" => @job_class.work_phase,
       "totals" => totals, "done" => done, "work_started_at" => @work_started_at.iso8601}
        .merge(result.to_h.transform_keys(&:to_s)).merge(@timing.to_h)
    end

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def initialize(actor_id)
    super()
    @actor_id = actor_id
    @enqueued_at = Time.current.iso8601
  end

  def perform
    set_locale
    return if self.class.with_run_lock { run }

    self.class.ensure_category
    attributes = {level: "warn", message: I18n.t("#{i18n_scope}.log_skipped", run: run_label),
                  payload: {"sub_category" => sub_category, "status" => "skipped"}}
    return queued_entry.update!(attributes) if queued_entry

    ::HitobitoLogEntry.create!(attributes.merge(category: log_category, subject_type: "Person", subject_id: @actor_id))
  end

  # Queues the run with its entry (status queued), both in one transaction,
  # so .status never sees the one without the other.
  def enqueue!(options = {})
    self.class.ensure_category
    ::HitobitoLogEntry.transaction do
      entry = ::HitobitoLogEntry.create!(category: log_category, level: "info", subject_type: "Person",
        subject_id: @actor_id, message: I18n.t("#{i18n_scope}.log_queued", run: run_label),
        payload: {"sub_category" => sub_category, "status" => "queued", "enqueued_at" => @enqueued_at})
      @entry_id = entry.id
      super({queue: queue_name}.merge(options)).tap do |job|
        entry.update_columns(payload: entry.payload.merge("delayed_job_id" => job.id))
      end
    end
  end

  # What the run is called in its messages ("alle", ...).
  def run_label = "alle"

  class << self
    # Holds the lock key around the block; answers false without running it
    # when another run holds it.
    def with_run_lock
      connection = ::ActiveRecord::Base.connection
      return false unless connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{lock_key})")
      end
      true
    end

    # Whether a process holds the lock key, i.e. a run works.
    def run_alive?
      ::ActiveRecord::Base.connection.select_value(<<~SQL).present?
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND granted AND objsubid = 1
          AND classid = #{lock_key >> 32} AND objid = #{lock_key & 0xFFFFFFFF}
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
      SQL
    end

    # The entry of a run that starts: status running, phase scan -- the
    # entry written as it was queued, if there is one.
    def start_entry(actor_id:, run:, timing:, entry: nil)
      ensure_category
      attributes = {level: "info", message: I18n.t("#{i18n_scope}.log_started", run: run),
                    payload: {"sub_category" => sub_category, "status" => "running", "phase" => "scan"}
                      .merge(timing.to_h)}
      return entry.tap { entry.update!(attributes) } if entry

      ::HitobitoLogEntry.create!(attributes.merge(category: log_category, subject_type: "Person",
        subject_id: actor_id))
    end

    # Writes the result of a run with its timing: into the run's entry, or a
    # new one (a run that worked at once). A cancelled run says how far it
    # came and who cancelled it.
    def log(result, actor_id:, run:, timing:, entry: nil, progress: nil)
      ensure_category
      cancelled = progress&.cancel_requested?
      status = cancelled ? "cancelled" : "finished"
      payload = if progress
        progress.payload(result, status).merge(progress.cancel)
      else
        result.to_h.transform_keys(&:to_s).merge(timing.to_h)
      end
      attributes = {level: (result.failed.zero? && !cancelled) ? "info" : "warn",
                    message: log_message(result, run: run, timing: timing, progress: cancelled && progress),
                    payload: payload.merge("sub_category" => sub_category, "status" => status)}
      return entry.update!(attributes) if entry

      ::HitobitoLogEntry.create!(attributes.merge(category: log_category, subject_type: "Person",
        subject_id: actor_id))
    end

    def log_message(result, run:, timing:, progress: nil)
      counts = result.to_h.except(:errors).merge(run: run, duration: format_duration(timing.duration))
      return I18n.t("#{i18n_scope}.log_message", **counts) unless progress

      by = ::Person.find_by(id: progress.cancel["cancel_requested_by"])
      first = figures.first
      I18n.t("#{i18n_scope}.log_cancelled", **counts, done: progress.done[first], total: progress.totals[first],
        by: by.to_s.presence || "?")
    end

    # Cancels the run: a run in the queue is taken out of it (and logged), a
    # running one is marked and stops after the item at hand. Answers
    # :dequeued, :requested or nil (no run).
    def cancel!(by:)
      entry = entries.order(:id).last
      if entry&.payload&.dig("status") == "running"
        with_locked_entry(entry) do |locked, current|
          locked.update_columns(payload: current.merge("cancel_requested_at" => Time.current.iso8601,
            "cancel_requested_by" => by.id))
        end
        return :requested
      end

      return nil if jobs.where(locked_at: nil).delete_all.zero?

      ensure_category
      attributes = {level: "warn", message: I18n.t("#{i18n_scope}.log_dequeued", by: by.to_s),
                    payload: {"sub_category" => sub_category, "status" => "cancelled",
                              "cancel_requested_at" => Time.current.iso8601, "cancel_requested_by" => by.id}}
      queued = entries.where("payload->>'status' = 'queued'").to_a
      if queued.any?
        queued.each { |queued_entry| queued_entry.update!(attributes) }
      else
        ::HitobitoLogEntry.create!(attributes.merge(category: log_category, subject_type: "Person",
          subject_id: by.id))
      end
      :dequeued
    end

    # Yields the entry locked for update with its current payload.
    def with_locked_entry(entry)
      ::HitobitoLogEntry.transaction do
        locked = ::HitobitoLogEntry.lock.find(entry.id)
        yield locked, locked.payload || {}
      end
    end

    # The category is also added where the wagon starts
    # (HitobitoWsjrdp2027::Wagon); adding it here too keeps the log working
    # when the classes are reloaded without that.
    def ensure_category = ::HitobitoLogEntry.categories |= [log_category]

    # The log entries of this kind of run, among the others of the category.
    def entries
      ::HitobitoLogEntry.where(category: log_category).where("payload->>'sub_category' = ?", sub_category)
    end

    # The queued and running Delayed::Jobs of this kind of run.
    def jobs = ::Delayed::Job.where("handler LIKE ?", "--- !ruby/object:#{name}\n%")

    # Whether a run is waiting or working.
    def running? = jobs.exists?

    # What the progress display shows: "waiting" (in the queue), "running"
    # (with totals, done, elapsed and an estimate of the rest; phase
    # "unknown" when a worker has taken the job but writes no progress),
    # "stale" (a running entry whose process holds no run lock any more: it
    # died), "lost" (a queued entry whose job is gone without having
    # started: the worker threw it away) or "idle"; and the last entry's
    # message.
    def status
      job = jobs.order(:id).first
      entry = entries.order(:id).last
      payload = entry&.payload || {}
      if payload["status"] == "running"
        if run_alive?
          return running_status(entry, payload).merge("cancelling" => payload["cancel_requested_at"].present?)
        end

        return {"state" => "stale", "message" => entry.message, "since" => entry.updated_at.iso8601}
      end
      if job&.locked_at
        # Taken by a worker that writes no progress (e.g. one still running
        # older code): running, without numbers.
        return {"state" => "running", "phase" => "unknown", "elapsed_seconds" => (Time.current - job.locked_at).round}
      end
      return {"state" => "waiting", "since" => job.created_at.iso8601} if job
      if payload["status"] == "queued"
        return {"state" => "lost", "since" => entry.created_at.iso8601, "entry_id" => entry.id}
      end

      {"state" => "idle", "message" => entry&.message, "entry_id" => entry&.id, "last_status" => payload["status"]}
    end

    def running_status(entry, payload)
      started = (payload["started_at"] && Time.zone.parse(payload["started_at"])) || entry.created_at
      work_started = payload["work_started_at"] && Time.zone.parse(payload["work_started_at"])
      totals = payload["totals"] || {}
      done = payload["done"] || {}
      {"state" => "running", "phase" => payload["phase"], "entry_id" => entry.id, "message" => entry.message,
       "totals" => totals, "done" => done,
       "elapsed_seconds" => (Time.current - started).round,
       "remaining_seconds" => remaining_seconds(work_started, done[pace], totals[pace])}
    end

    # The rest, at the pace of what was done so far.
    def remaining_seconds(work_started, done, total)
      return nil if work_started.nil? || done.to_i.zero? || total.to_i.zero?

      ((Time.current - work_started) / done.to_f * (total.to_i - done.to_i)).round
    end

    # "850 ms", "12,3 s", "4 min 12 s", "1 h 3 min".
    def format_duration(seconds)
      seconds = seconds.to_f
      if seconds < 1 then "#{(seconds * 1000).round} ms"
      elsif seconds < 60 then "#{format("%.1f", seconds).tr(".", ",")} s"
      elsif seconds < 3600 then "#{(seconds / 60).floor} min #{(seconds % 60).round} s"
      else
        "#{(seconds / 3600).floor} h #{((seconds % 3600) / 60).round} min"
      end
    end
  end

  private

  # Scans what to work on; answers [items, totals] (totals by figure).
  def prepare = raise(NotImplementedError)

  # Works on the items, ticking `progress`; answers the result (with
  # #failed, #to_h).
  def work(items, progress) = raise(NotImplementedError)

  # The result of a run that did nothing yet.
  def empty_result = raise(NotImplementedError)

  # After the work (not after a cancel): anything left to note.
  def finish(items) = nil

  def run
    timing = Timing.new(enqueued_at: @enqueued_at)
    entry = self.class.start_entry(actor_id: @actor_id, run: run_label, timing: timing, entry: queued_entry)
    items, totals = timing.measure(:scan) { prepare }
    progress = Progress.new(entry, totals, timing, self.class)
    result = empty_result
    unless progress.write(result)
      result = timing.measure(work_phase.to_sym) { work(items, progress) }
      finish(items) unless progress.cancel_requested?
    end
    self.class.log(result, actor_id: @actor_id, run: run_label, timing: timing.finish, entry: entry,
      progress: progress)
  rescue => e
    entry&.update_columns(message: I18n.t("#{i18n_scope}.log_failed", run: run_label, error: e.message.truncate(200)),
      payload: (entry.payload || {}).merge("status" => "failed", "error" => e.message.truncate(500)),
      level: ::HitobitoLogEntry.levels.fetch("error"), updated_at: Time.current)
    raise
  end

  # The entry written as this run was queued, while it still says queued.
  def queued_entry
    return @queued_entry if defined?(@queued_entry)

    @queued_entry = @entry_id && self.class.entries.where("payload->>'status' = 'queued'").find_by(id: @entry_id)
  end
end
