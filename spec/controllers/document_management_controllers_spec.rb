# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The overview of the Dokumentenverwaltung in Einstellungen, for admins only:
# the check of all documents' files in the background.
describe DocumentManagementController, type: :controller do
  before_all(setup_fixtures: true) do
    @admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person
  end

  let(:admin) { @admin }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:job) { Wsjrdp2027::CheckDocumentFilesJob }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    sign_in(admin)
  end

  after { FileUtils.rm_rf(root) }

  it "is refused to who is no admin" do
    sign_in(people(:cmt_leader))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "queues a check of all files in the background" do
    expect { post :check_files }.to change(Delayed::Job, :count).by(1)

    expect(response).to redirect_to(document_management_path)
    expect(flash[:notice]).to be_present
    expect(Delayed::Job.last.queue).to eq("documents")
  end

  it "queues no second check while one waits" do
    job.new(admin.id).enqueue!

    expect { post :check_files }.not_to change(Delayed::Job, :count)
    expect(flash[:alert]).to be_present
  end

  it "reports a waiting check" do
    job.new(admin.id).enqueue!

    get :check_files_progress

    expect(response.parsed_body).to include("state" => "waiting")
  end

  it "takes a waiting check out of the queue" do
    job.new(admin.id).enqueue!

    expect { post :check_files_cancel, format: :json }.to change(Delayed::Job, :count).by(-1)
    expect(response.parsed_body).to include("outcome" => "dequeued", "state" => "idle", "last_status" => "cancelled")
  end

  it "marks a document whose file is gone missing, and logs the run" do
    document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
      {subject: people(:yp_a_1), key: "deregistration", filename: "a.pdf"})
    Wsjrdp2027::DocumentStore.path_for(document).delete

    job.new(admin.id).perform

    expect(document.reload.file_status).to eq("missing")
    expect(job.entries.last.payload).to include("status" => "finished", "totals" => {"files" => 1},
      "done" => {"files" => 1}, "missing" => 1)
  end
end
