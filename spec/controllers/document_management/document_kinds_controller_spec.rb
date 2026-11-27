# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tab Arten of the main section Dokumente: the kinds of document, for
# admins only.
describe DocumentManagement::DocumentKindsController, type: :controller do
  before_all(setup_fixtures: true) do
    @admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person
  end

  let(:medical) { wsjrdp_document_kinds(:medical) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:form) do
    {label: "Brief", subject_type: "Person", key: "brief", secondary_key: "", position: "100",
     readable_by: ["", "person", "log"], writable_by: ["", "log"], deletable_by: ["", "log"],
     content_types: ["", "application/pdf", "image/*"], extensions: [""], max_upload_size_mb: "5",
     rules: {"n7" => {roles: ["", "UL"], offer_to: ["", "update"], not_for_status: [""], required: "1",
                      missing_tag: "", missing_tag_from_status: [""]},
             "0" => {roles: [""], offer_to: ["", "log"], not_for_status: ["", "registered"],
                     missing_tag: "Brief-fehlt", missing_tag_from_status: ["", "reviewed"], remove_on_upload: "1"},
             "1" => {roles: [""], offer_to: [""], not_for_status: [""], missing_tag: "",
                     missing_tag_from_status: [""]}},
     additional_info: '{"note": "x"}'}
  end

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    sign_in(@admin)
  end

  after { FileUtils.rm_rf(root) }

  def store_medical
    Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"), {subject: people(:yp_a_1), key: "medical",
      filename: "a.pdf"})
  end

  it "is refused to who is no admin" do
    sign_in(people(:cmt_leader))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "sorts the kinds by their keys" do
    get :index, params: {s: "k"}

    labels = controller.send(:kinds).page.map(&:label)
    expect(labels.first).to eq("Vertrag (Anmeldung)")
    expect(labels.last).to eq("SEPA-Mandat")
  end

  it "answers a row's frame with the form alone, saving back to the list it was opened in" do
    request.headers["Turbo-Frame"] = "bkframe-dk-#{medical.id}"
    request.env["HTTP_REFERER"] = "http://www.example.com/document_management/document_kinds?s=lb"

    get :show, params: {id: medical.id}

    expect(response).to render_template(layout: false)
    expect(controller.send(:return_to)).to eq("/document_management/document_kinds?s=lb")
  end

  it "starts a new kind for a person, after the last position" do
    get :new

    expect(assigns(:kind)).to have_attributes(subject_type: "Person",
      position: WsjrdpDocumentKind.maximum(:position) + 10)
  end

  # As JSON: a form body keeps the order of the cards, a query string would sort them.
  it "creates a kind with its rules in the order of their cards, and keeps additional_info" do
    post :create, params: {kind: form}, as: :json

    kind = WsjrdpDocumentKind.find_by!(key: "brief")
    expect(response).to redirect_to("/document_management/document_kinds/#{kind.id}")
    expect(kind).to have_attributes(label: "Brief", readable_by: %w[person log], writable_by: %w[log],
      content_types: %w[application/pdf image/*], extensions: nil, max_upload_size_mb: 5, additional_info: {})
    expect(kind.role_rules).to eq([
      {"roles" => %w[UL], "offer_to" => %w[update], "required" => true},
      {"offer_to" => %w[log], "not_for_status" => %w[registered],
       "missing_tag" => {"tag" => "Brief-fehlt", "from_status" => %w[reviewed], "remove_on_upload" => true}}
    ])
  end

  it "shows the form again with what is wrong" do
    expect { post :create, params: {kind: form.merge(key: "Letter", readable_by: ["Log!"])} }
      .not_to change(WsjrdpDocumentKind, :count)

    expect(response).to have_http_status(422)
    expect(assigns(:kind).errors).to be_present
  end

  it "saves back to the list it was opened in" do
    patch :update, params: {id: medical.id, return_to: "/document_management/document_kinds?s=lb",
                            kind: form.merge(label: "Medizin", key: "medicine").except(:rules)}

    expect(response).to redirect_to("/document_management/document_kinds?s=lb")
    expect(medical.reload).to have_attributes(label: "Medizin", key: "medicine", role_rules: [])
  end

  it "fixes the keys once documents have them, and goes back to no page of another site" do
    store_medical

    patch :update, params: {id: medical.id, return_to: "https://elsewhere.example/x", kind: form.merge(key: "other")}

    expect(response).to redirect_to("/document_management/document_kinds/#{medical.id}")
    expect(medical.reload).to have_attributes(key: "medical", label: "Brief")
  end

  it "deletes a kind without documents" do
    expect { delete :destroy, params: {id: wsjrdp_document_kinds(:sepa).id} }
      .to change(WsjrdpDocumentKind, :count).by(-1)
  end

  it "keeps a kind with documents" do
    store_medical

    expect { delete :destroy, params: {id: medical.id} }.not_to change(WsjrdpDocumentKind, :count)
    expect(flash[:alert]).to be_present
  end
end
