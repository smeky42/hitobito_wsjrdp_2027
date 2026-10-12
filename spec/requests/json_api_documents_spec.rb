# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# GET /api/documents and /api/documents/:id (DocumentResource): an API key
# reads a document with the scope people:documents and an acting person who
# may read it.
describe "JSON:API documents", type: :request do
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:acting_person) { people(:cmt_leader) }
  let(:scopes) { %w[people people:documents] }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "Skript", permission: "layer_and_below_read",
      acting_person: acting_person, scopes: scopes)
  end
  # Before the documents below are stored.
  before { allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root) }

  let!(:medical) { store(key: "medical") }
  let!(:hidden) { store(key: "finance_note", readable_by: %w[finance]) }

  after { FileUtils.rm_rf(root) }

  def store(**attrs)
    Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4\n%%EOF\n"),
      {subject: person, filename: "scan.pdf"}.merge(attrs))
  end

  def api_get(path)
    get path, headers: {"Accept" => "application/vnd.api+json", "X-Token" => token.plain_token}
  end

  def ids = JSON.parse(response.body)["data"].map { |entry| entry["id"].to_i }

  it "lists the documents of a person the acting person may read" do
    api_get "/api/documents?filter[subject_id]=#{person.id}"

    expect(response).to have_http_status(200)
    expect(ids).to eq([medical.id])
    expect(JSON.parse(response.body)["data"].first["attributes"])
      .to include("key" => "medical", "subject_id" => person.id, "filename" => "scan.pdf", "status" => "current")
  end

  it "shows one document and refuses one the acting person may not read" do
    api_get "/api/documents/#{medical.id}"
    expect(response).to have_http_status(200)

    api_get "/api/documents/#{hidden.id}"
    expect(response).to have_http_status(403)
  end

  it "needs filter[subject_id] for the list" do
    api_get "/api/documents"

    expect(response).to have_http_status(400)
  end

  context "without the scope people:documents" do
    let(:scopes) { %w[people people:log] }

    it "reads nothing" do
      api_get "/api/documents?filter[subject_id]=#{person.id}"
      expect(response).to have_http_status(403)

      api_get "/api/documents/#{medical.id}"
      expect(response).to have_http_status(403)
    end
  end

  context "without an acting person" do
    let(:acting_person) { nil }

    it "reads nothing, as the scope is an extra" do
      api_get "/api/documents/#{medical.id}"

      expect(response).to have_http_status(403)
    end
  end
end
