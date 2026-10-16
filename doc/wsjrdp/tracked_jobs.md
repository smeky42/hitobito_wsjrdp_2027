# Tracked jobs

A tracked job is a job in the background (Delayed::Job) whose runs can be
followed and cancelled from a page: each run is one `HitobitoLogEntry`,
kept up to date while it works, which a progress display reads. The
building blocks are not tied to any kind of work:

| Part | File |
|---|---|
| The job's base class | `app/domain/wsjrdp/tracked_job.rb` (`Wsjrdp::TrackedJob`) |
| The progress display | `app/views/shared/wsjrdp/_tracked_job_progress.html.haml` |
| The controller side | `app/controllers/concerns/wsjrdp/tracked_job_endpoints.rb` (`Wsjrdp::TrackedJobEndpoints`) |
| The default texts | `wsjrdp.tracked_job.*` in `config/locales/wsjrdp_2027.de.yml` |

In use: `Wsjrdp2027::RegisterDocumentsJob` (registering the registration
uploads) and `Wsjrdp2027::CheckDocumentFilesJob` (checking the files of all
documents), both described in `doc/wsjrdp/documents.md`.

## A run

1. `job.enqueue!` writes the run's log entry (status `queued`, with the id
   of its Delayed::Job) and queues the job, both in one transaction.
2. A worker starts the run: it takes the lock (`lock_key`, a session-level
   PostgreSQL advisory lock), takes over the entry (status `running`, phase
   `scan`), and calls `#prepare` for the items and their totals.
3. In `work_phase` it calls `#work`, which ticks the progress
   (`progress.tick(result, files: 3)`); the progress is written at most once
   a second and answers `:stop` when the run is to be cancelled.
4. At the end the entry gets the result, the counts and the timing (status
   `finished`, or `cancelled`; `failed` with the error when it raised).

A second run while one works is skipped and logged as such. `.status`
answers what the display shows: `waiting`, `running` (with totals, done,
elapsed time and an estimate of the rest at the pace of `pace`), `stale` (a
running entry whose process holds the lock no more: it died), `lost` (a
queued entry whose job is gone without having started: the worker threw it
away, typically one whose code does not know the class) or `idle`.
`.cancel!` takes a waiting run out of the queue or marks a running one,
which stops after the item at hand.

## Writing one

```ruby
class Wsjrdp2027::SomethingJob < Wsjrdp::TrackedJob
  self.log_category = "documents"          # a HitobitoLogEntry category the wagon registers
  self.sub_category = "something"          # tells its runs from others of the category
  self.queue_name = "documents"
  self.lock_key = 2_027_000_004            # unique per job
  self.i18n_scope = "some.scope"           # log_* texts; progress.* falls back to wsjrdp.tracked_job.progress.*
  self.work_phase = "work"
  self.figures = %w[files]                 # the counters, in display order
  self.pace = "files"                      # the counter the rest is estimated by

  private

  def prepare = [items, {"files" => items.size}]

  def work(items, progress)
    items.each do |item|
      ...
      break if progress.tick(result, files: 1) == :stop
    end
    result
  end

  def empty_result = result                # responds to #failed and #to_h (the counts for the texts)
end
```

Its texts under `i18n_scope`: `log_queued`, `log_started`, `log_running`
(`%{done}`, `%{total}` of the first figure), `log_message` and
`log_cancelled` (the counts of the result, `%{run}`, `%{duration}`;
cancelled also `%{done}`, `%{total}`, `%{by}`), `log_skipped`,
`log_dequeued`, `log_failed`; optionally `progress.*` and `cancel.*`.

The page renders the display and the controller answers it:

```haml
= render "shared/wsjrdp/tracked_job_progress", job: Wsjrdp2027::SomethingJob,
  id: "something-progress", progress_url: something_progress_path, cancel_url: cancel_something_path
```

```ruby
include Wsjrdp::TrackedJobEndpoints

def start = enqueue_tracked_job(Wsjrdp2027::SomethingJob.new(current_user.id), back: some_path,
  texts: {enqueued: "...", running: "..."})
def progress = render_tracked_job_status(Wsjrdp2027::SomethingJob)
def cancel = cancel_tracked_job(Wsjrdp2027::SomethingJob, back: some_path)
```

The display takes further locals: `figures` (the counters shown, default
`job.figures`; elapsed time and rest always follow), `bar` (the counter the
bar follows, default `job.pace`), `texts` (overrides for this box),
`reload: false` (no reload link when a run is done); without `cancel_url`
there is no "Abbrechen".
