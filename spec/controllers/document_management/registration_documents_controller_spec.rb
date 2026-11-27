# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tab Anmelde-Dokumente of the Dokumentenverwaltung in Einstellungen, for
# admins only: registers the registration uploads as documents, at once or in
# the background. The person has one upload, a Medizinbogen.
describe DocumentManagement::RegistrationDocumentsController, type: :controller do
  before_all(setup_fixtures: true) do
    @admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person
  end

  let(:admin) { @admin }
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:folder) { root.join("person/pdf/#{person.id}") }
  let(:name) { "2025-06-28-14-38-32--#{person.id}-medical.pdf" }
  let(:job) { Wsjrdp2027::RegisterDocumentsJob }
  let(:run_entries) { HitobitoLogEntry.where(category: "documents") }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    FileUtils.mkdir_p(folder)
    folder.join(name).write("%PDF-1.4")
    person.update_columns(upload_medical_pdf: "/x/private/uploads/person/pdf/#{person.id}/#{name}")
    sign_in(admin)
  end

  after { FileUtils.rm_rf(root) }

  def chain_filter(tree)
    schema = DocumentManagement::RegistrationChainsFilterSchema
    schema.encode(Wsjrdp::Filtering::Query.parse(tree), schema: schema.bound)
  end

  it "is refused to who is no admin" do
    sign_in(people(:cmt_leader))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "shows the chains of the registration uploads, filtered by the CNF filter" do
    get :index, params: {f: chain_filter([[["person_id", "eq", person.id]]])}

    expect(controller.send(:chains).page.map { |chain| [chain.id, chain.state] }).to eq([["#{person.id}-medical", :new]])
  end

  it "registers the chosen chains with the rights of their kinds and logs the run" do
    post :register, params: {chain_ids: ["#{person.id}-medical"], rights: {medical: {readable_by: ["", "finance"]}}}

    expect(response).to redirect_to(%r{/document_management/registration_documents})
    expect(WsjrdpDocument.of_subject(person).sole).to have_attributes(key: "medical", status: "current",
      origin: "import", readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log])
    entry = job.entries.last
    expect(entry.payload).to include("duration_seconds", "started_at", "finished_at")
    expect(entry.payload["phase_seconds"].keys).to contain_exactly("scan", "register")
    expect(flash[:notice]).to be_present
  end

  it "registers every chain of the filter with select_all" do
    post :register, params: {select_all: "1", f: chain_filter([[["person_id", "eq", person.id]]])}

    expect(response).to redirect_to(%r{f=})
    expect(WsjrdpDocument.of_subject(person).count).to eq(1)
  end

  it "registers a large selection in the background" do
    stub_const("DocumentManagement::RegistrationDocumentsController::SYNC_LIMIT", 0)

    expect { post :register, params: {select_all: "1", f: chain_filter([[["person_id", "eq", person.id]]])} }
      .to change(Delayed::Job, :count).by(1)
    expect(Delayed::Job.last.payload_object.instance_variable_get(:@chain_ids)).to eq(["#{person.id}-medical"])
  end

  it "registers all in the background, as the form's operation too" do
    expect { post :register, params: {operation: "register_all"} }.to change(Delayed::Job, :count).by(1)

    expect(flash[:notice]).to be_present
    expect(Delayed::Job.last.queue).to eq("documents")
  end

  it "lists only its own runs among the entries of the category" do
    other = HitobitoLogEntry.create!(category: "documents", level: "info", message: "Anderer Eintrag", subject: admin,
      payload: {"sub_category" => "other"})

    post :register, params: {chain_ids: ["#{person.id}-medical"]}

    expect(controller.send(:runs).size).to eq(1)
    expect(controller.send(:runs)).not_to include(other)
  end

  it "reports the progress of a run in the background" do
    job.new(admin.id).enqueue!

    get :progress

    expect(response.parsed_body).to include("state" => "waiting")
  end

  it "takes a waiting run out of the queue" do
    job.new(admin.id).enqueue!

    expect { post :cancel, format: :json }.to change(Delayed::Job, :count).by(-1)
    expect(response.parsed_body).to include("outcome" => "dequeued", "state" => "idle", "last_status" => "cancelled")
  end

  # The states of a run in the background, as the progress display reads them.
  describe "the status of a run" do
    def status = job.status

    it "is idle without a run, waiting while queued, running once a worker took it" do
      expect(status).to include("state" => "idle")
      job.new(admin.id).enqueue!
      expect(status).to include("state" => "waiting")
      Delayed::Job.last.update_columns(locked_at: 3.seconds.ago, locked_by: "spec")
      expect(status).to include("state" => "running", "phase" => "unknown")
    end

    it "is lost when the worker threw a queued run away before it started" do
      job.new(admin.id).enqueue!
      entry = run_entries.last
      expect(entry.payload).to include("status" => "queued", "delayed_job_id" => Delayed::Job.last.id)

      Delayed::Job.delete_all

      expect(status).to include("state" => "lost", "entry_id" => entry.id)
    end

    it "is stale for a running entry without a process holding the run lock, else running with an estimate" do
      HitobitoLogEntry.create!(category: "documents", level: "info", message: "x", subject: admin,
        payload: {"sub_category" => "registration_documents_sync", "status" => "running", "phase" => "register",
                  "work_started_at" => 10.seconds.ago.iso8601, "done" => {"people" => 0, "files" => 1},
                  "totals" => {"people" => 1, "files" => 4}})

      expect(status).to include("state" => "stale")
      job.with_run_lock { expect(status).to include("state" => "running", "remaining_seconds" => be_between(25, 35)) }
    end
  end

  describe "a run in the background" do
    it "takes over the entry written as it was queued, and registers every chain" do
      job.new(admin.id).enqueue!
      queued = Delayed::Job.last.payload_object
      Delayed::Job.delete_all

      expect { queued.perform }.not_to change(run_entries, :count)
      expect(run_entries.last.payload).to include("status" => "finished",
        "totals" => include("people" => 1, "files" => 1), "done" => include("people" => 1, "chains" => 1),
        "enqueued_at" => be_present, "waited_seconds" => be_present)
      expect(WsjrdpDocument.of_subject(person).count).to eq(1)
    end

    it "stops after the chain at hand when cancelled" do
      second = people(:yp_a_2)
      second_name = "2025-06-28-14-38-32--#{second.id}-medical.pdf"
      FileUtils.mkdir_p(root.join("person/pdf/#{second.id}"))
      root.join("person/pdf/#{second.id}/#{second_name}").write("%PDF-1.4")
      second.update_columns(upload_medical_pdf: "/x/private/uploads/person/pdf/#{second.id}/#{second_name}")
      # Cancelled as soon as the first chain is done.
      allow_any_instance_of(Wsjrdp::TrackedJob::Progress).to receive(:tick).and_wrap_original do |m, *args, **counts|
        job.cancel!(by: admin)
        m.receiver.instance_variable_set(:@written_at, nil)
        m.call(*args, **counts)
      end

      job.new(admin.id).perform

      expect(run_entries.last.payload).to include("status" => "cancelled", "cancel_requested_by" => admin.id,
        "done" => include("chains" => 1), "totals" => include("chains" => 2))
      expect(WsjrdpDocument.where(origin: "import").count).to eq(1)
      expect(job.status).to include("state" => "idle", "last_status" => "cancelled")
    end

    it "runs once at a time and logs a run it skips" do
      other = ActiveRecord::Base.connection_pool.checkout
      other.select_value("SELECT pg_advisory_lock(#{job.lock_key})")

      expect(job.run_alive?).to be(true)
      job.new(admin.id).perform
      expect(run_entries.last.message).to include("übersprungen")
      expect(WsjrdpDocument.where(origin: "import")).to be_empty
    ensure
      other&.select_value("SELECT pg_advisory_unlock(#{job.lock_key})")
      ActiveRecord::Base.connection_pool.checkin(other) if other
    end

    it "keeps a cancel mark the job's progress writes over" do
      entry = HitobitoLogEntry.create!(category: "documents", level: "info", message: "x", subject: admin,
        payload: {"sub_category" => "registration_documents_sync", "status" => "running"})
      job.cancel!(by: admin)
      progress = Wsjrdp::TrackedJob::Progress.new(entry, {}, Wsjrdp::TrackedJob::Timing.new, job)

      expect(progress.write(Wsjrdp2027::RegistrationDocuments::Import.new.register([]))).to be(true)
      expect(entry.reload.payload).to include("cancel_requested_by" => admin.id, "status" => "running")
      job.with_run_lock { expect(job.status).to include("state" => "running", "cancelling" => true) }
    end
  end

  describe "a file nothing names" do
    let(:loose) { "2025-05-01-10-00-00--#{person.id}-medical.pdf" }
    let(:relative) { "person/pdf/#{person.id}/#{loose}" }

    before do
      folder.join(loose).write("%PDF-1.4 loose")
      FileUtils.touch(folder.join(loose), mtime: 1.day.ago.to_time)
    end

    it "is listed to decide on" do
      get :index

      expect(controller.send(:scan).anomalies.map { |a| [a.kind, a.path] }).to include([:file_without_row, relative])
    end

    it "is sent to look at, sandboxed" do
      get :unregistered_file, params: {path: relative}

      expect(response).to have_http_status(200)
      expect(response.body).to eq("%PDF-1.4 loose")
      expect(response.headers["Content-Security-Policy"]).to eq("sandbox")
    end

    it "is adopted as an old file of its chain, with a note of who adopted it" do
      post :adopt_file, params: {path: relative}

      expect(flash[:notice]).to include(relative)
      old, current = WsjrdpDocument.of_subject(person).order(:created_at).to_a
      expect(old).to have_attributes(relative_storage_file_path: relative, status: "superseded")
      expect(old.additional_info["registration_upload"]["reviewed_by"]).to eq("type" => "Person", "id" => admin.id)
      expect(current).to have_attributes(status: "current", replaces_id: old.id)
    end

    it "is set aside to the quarantine" do
      post :set_aside_file, params: {path: relative}

      expect(flash[:notice]).to include(relative)
      expect(folder.join(loose)).not_to exist
      expect(root.join("quarantine", relative).read).to eq("%PDF-1.4 loose")
    end

    it "is not a file a column names" do
      get :unregistered_file, params: {path: "person/pdf/#{person.id}/#{name}"}

      expect(flash[:alert]).to be_present
    end

    it "is no path outside the person folders" do
      post :set_aside_file, params: {path: "../../etc/passwd"}

      expect(flash[:alert]).to be_present
      expect(folder.join(name)).to exist
    end
  end
end
