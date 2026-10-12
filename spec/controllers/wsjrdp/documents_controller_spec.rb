# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::DocumentsController, type: :controller do
  let(:person) { people(:yp_a_1) }
  # An upload root of its own, so the examples write nothing below the
  # wagon's private/uploads.
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:pdf) { "%PDF-1.4\n%%EOF\n".b }

  before { allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root) }
  after { FileUtils.rm_rf(root) }

  def store(content = pdf, **attrs)
    Wsjrdp2027::DocumentStore.store!(StringIO.new(content),
      {subject: person, key: "letter", filename: "scan.pdf"}.merge(attrs))
  end

  def upload(content = pdf, filename: "Scan.pdf", type: "application/pdf")
    file = Tempfile.new(["upload", File.extname(filename)])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: filename)
  end

  describe "GET show" do
    it "sends a PDF inline, not to be cached, in a sandbox" do
      sign_in(person)
      document = store

      get :show, params: {id: document.id}

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(pdf)
      expect(response.headers["Content-Disposition"]).to start_with("inline")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Content-Security-Policy"]).to eq("sandbox")
    end

    it "sends other types and ?download=1 as an attachment" do
      sign_in(person)
      html = store("<html><script>alert(1)</script></html>", key_number: 1, filename: "brief.html",
        content_type: "text/html")

      get :show, params: {id: html.id}
      expect(response.headers["Content-Disposition"]).to start_with("attachment")

      get :show, params: {id: store.id, download: 1}
      expect(response.headers["Content-Disposition"]).to start_with("attachment")
    end

    it "refuses who may not read the document" do
      sign_in(people(:yp_a_2))

      expect { get :show, params: {id: store.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "answers 404 for a document whose file is known missing" do
      sign_in(person)
      document = store
      document.update!(file_status: "missing")

      get :show, params: {id: document.id}

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 when the file is missing" do
      sign_in(person)
      document = store
      File.delete(document.absolute_storage_file_path)

      get :show, params: {id: document.id}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create" do
    let(:params) do
      {subject_type: "Person", subject_id: person.id, key: "letter", key_number: 0, secondary_key: "",
       secondary_key_number: 0, comment: "Neu", file: upload}
    end

    it "stores the upload with its author and comment" do
      sign_in(person)

      expect { post :create, params: {document: params} }.to change(WsjrdpDocument, :count).by(1)

      document = WsjrdpDocument.last
      expect(document).to have_attributes(subject: person, key: "letter", filename: "Scan.pdf", comment: "Neu",
        author: person, origin: "ui", content_type: "application/pdf",
        readable_by: %w[person log], writable_by: %w[person log], deletable_by: %w[log])
      expect(File.binread(document.absolute_storage_file_path)).to eq(pdf)
      expect(flash[:notice]).to be_present
    end

    it "ignores lists in the request" do
      sign_in(person)

      post :create, params: {document: params.merge(readable_by: %w[everybody])}

      expect(WsjrdpDocument.last.readable_by).to eq(%w[person log])
    end

    it "replaces a document" do
      sign_in(person)
      old = store

      post :create, params: {document: {replaces_id: old.id, file: upload(filename: "neu.pdf")}}

      expect(old.reload.status).to eq("superseded")
      expect(WsjrdpDocument.last).to have_attributes(replaces_id: old.id, key: "letter", status: "current")
    end

    it "refuses who may not write a document of the subject and writes nothing" do
      sign_in(people(:yp_a_2))

      expect { post :create, params: {document: params} }.to raise_error(CanCan::AccessDenied)
      expect(root.glob("**/*").select(&:file?)).to be_empty
    end

    it "names what is wrong" do
      sign_in(person)
      store

      post :create, params: {document: params}

      expect(flash[:alert]).to include("aktuelles Dokument")
    end

    it "refuses an upload above the limit" do
      sign_in(person)
      allow(Wsjrdp2027::DocumentStore).to receive(:max_upload_size).and_return(4)

      expect { post :create, params: {document: params} }.not_to change(WsjrdpDocument, :count)
      expect(flash[:alert]).to include("zu groß")
    end

    context "of a kind" do
      let(:kind_params) { params.merge(key: "medical") }

      it "takes the kind's rights and lets only who it names write" do
        sign_in(person)
        expect { post :create, params: {document: kind_params} }.to raise_error(CanCan::AccessDenied)

        sign_in(people(:cmt_leader))
        post :create, params: {document: kind_params}

        expect(WsjrdpDocument.last).to have_attributes(key: "medical",
          readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log])
      end

      it "refuses a file the kind does not accept" do
        sign_in(people(:cmt_leader))

        expect {
          post :create, params: {document: kind_params.merge(file: upload("text", filename: "a.txt", type: "text/plain"))}
        }.not_to change(WsjrdpDocument, :count)
        expect(flash[:alert]).to include("application/pdf")
      end
    end

    context "by an admin" do
      before { sign_in(Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person) }

      it "takes the lists given" do
        post :create, params: {document: params.merge(readable_by: ["", "log", "finance_audit"], deletable_by: [""])}

        expect(WsjrdpDocument.last).to have_attributes(readable_by: %w[log finance_audit],
          writable_by: %w[person log], deletable_by: %w[log])
      end

      it "takes a list given as text" do
        post :create, params: {document: params.merge(writable_by: "log, finance")}

        expect(WsjrdpDocument.last.writable_by).to eq(%w[log finance])
      end

      it "refuses an invalid entry" do
        expect {
          post :create, params: {document: params.merge(readable_by: ["", "Log!"])}
        }.not_to change(WsjrdpDocument, :count)
        expect(flash[:alert]).to include("Log!")
      end
    end
  end
end
