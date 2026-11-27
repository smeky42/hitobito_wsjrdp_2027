# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tab Alle of the main section Dokumente: every stored document, for
# admins only.
describe DocumentManagement::DocumentsController, type: :controller do
  before_all(setup_fixtures: true) do
    @admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person
  end

  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    sign_in(@admin)
  end

  after { FileUtils.rm_rf(root) }

  def store(key, **options)
    Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 #{SecureRandom.hex(4)}"),
      {subject: person, key: key, filename: "#{key}.pdf"}.merge(options))
  end

  def filter(tree)
    schema = DocumentManagement::DocumentsFilterSchema
    schema.encode(Wsjrdp::Filtering::Query.parse(tree), schema: schema.bound)
  end

  def shown = controller.send(:documents).page.to_a

  it "is refused to who is no admin" do
    sign_in(people(:cmt_leader))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "lists every document, a deleted one too" do
    document = store("deregistration")
    Wsjrdp2027::DocumentStore.hide!(document)

    get :index

    expect(shown).to include(document)
  end

  it "shows one document" do
    document = store("deregistration")

    get :show, params: {id: document.id}

    expect(response).to have_http_status(200)
    expect(assigns(:document)).to eq(document)
  end

  describe "the filter on the kind" do
    let!(:known) { store("medical") }
    let!(:unknown) { store("deregistration") }

    it "finds the documents of a kind" do
      get :index, params: {f: filter([[["kind", "in", "medical"]]])}

      expect(shown).to eq([known])
    end

    it "finds the documents of no kind" do
      get :index, params: {f: filter([[["kind", "in", "_unknown"]]])}

      expect(shown).to eq([unknown])
    end

    it "finds the documents whose file is missing with the quick filter" do
      unknown.update_columns(file_status: WsjrdpDocument::FILE_MISSING)
      preset = DocumentManagement::DocumentsFilterSchema::PRESETS.find { |p| p[:key] == "file_missing" }

      get :index, params: {f: filter(preset[:slots])}

      expect(shown).to eq([unknown])
    end
  end

  # The oldest upload has the highest id, so only the upload time puts it last.
  describe "the order" do
    let!(:documents) do
      newer, newest, older = Array.new(3) { |i| store("deregistration", key_number: i, filename: "#{i}.pdf") }
      older.update_columns(created_at: 2.days.ago)
      [newer, newest].each { |document| document.update_columns(created_at: 1.day.ago.beginning_of_minute) }
      [newest, newer, older]
    end

    it "is the newest upload first, then the highest id" do
      get :index, params: {s: ""}

      expect(shown & documents).to eq(documents)
    end

    it "is the same after a sort that leaves the documents equal" do
      get :index, params: {s: "kd"}

      expect(shown & documents).to eq(documents)
    end
  end
end
