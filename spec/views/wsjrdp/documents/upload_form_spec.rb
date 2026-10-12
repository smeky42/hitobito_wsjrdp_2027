# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe "wsjrdp/documents/_upload_form", type: :view do
  let(:person) { people(:yp_a_1) }

  let(:viewer) { person }

  before { allow(view).to receive(:current_ability).and_return(Ability.new(viewer)) }

  def form = Capybara.string(rendered).find("form.wsjrdp-document-upload")

  it "posts a file into a slot of a subject" do
    render partial: "wsjrdp/documents/upload_form",
      locals: {subject: person, key: "deregistration", key_number: 2, secondary_key: "signed_form"}

    expect(form[:action]).to end_with("/documents")
    expect(form[:enctype]).to eq("multipart/form-data")
    expect(form).to have_field("document[subject_type]", type: :hidden, with: "Person")
    expect(form).to have_field("document[subject_id]", type: :hidden, with: person.id.to_s)
    expect(form).to have_field("document[key]", type: :hidden, with: "deregistration")
    expect(form).to have_field("document[key_number]", type: :hidden, with: "2")
    expect(form).to have_field("document[secondary_key]", type: :hidden, with: "signed_form")
    expect(form).to have_field("document[secondary_key_number]", type: :hidden, with: "0")
    expect(form).to have_field("document[file]", type: :file)
    expect(form).to have_button("Hochladen")
  end

  it "replaces a document" do
    document = WsjrdpDocument.new(id: 42, subject: person, key: "medical")

    render partial: "wsjrdp/documents/upload_form", locals: {replaces: document}

    expect(form).to have_field("document[replaces_id]", type: :hidden, with: "42")
    expect(form).to have_no_field("document[key]", type: :hidden)
    expect(form).to have_button("Ersetzen")
  end

  it "offers the rights lists to admins only" do
    render partial: "wsjrdp/documents/upload_form", locals: {subject: person, key: "letter"}
    expect(form).to have_no_field("document[readable_by][]", visible: :all)
  end

  context "for an admin" do
    let(:viewer) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    it "offers the rights lists" do
      render partial: "wsjrdp/documents/upload_form", locals: {subject: person, key: "letter"}

      %w[readable_by writable_by deletable_by].each do |list|
        expect(form).to have_select("document[#{list}][]", visible: :all)
      end
    end
  end
end
