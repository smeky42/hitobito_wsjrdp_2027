# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The upload page sends a stored document from the path the upload page
# stored, wherever it lies; a missing file is not found.
describe Person::UploadController, type: :controller do
  let(:person) { people(:yp_a_1) }
  # A folder of its own stands in for the person's upload folder, so the
  # examples write nothing below the wagon's private/uploads.
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:folder) { root.join("person", "pdf", person.id.to_s) }
  let(:file) { folder.join("2026-10-10-12-00-00--#{person.id}-medical.pdf") }

  def show_medical = get(:show_medical, params: {group_id: person.primary_group_id, id: person.id})

  before do
    sign_in(person)
    allow_any_instance_of(described_class).to receive(:generate_file_path).and_return("#{folder}/")
  end

  after { FileUtils.rm_rf(root) }

  it "sends a document from the person's folder" do
    FileUtils.mkdir_p(folder)
    File.binwrite(file, "%PDF-1.4 spec")
    person.update_columns(upload_medical_pdf: file.to_s)

    show_medical

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("%PDF-1.4 spec")
  end

  # A path from production, below another wagon root, as a development setup
  # with the files synced elsewhere has it.
  it "sends a document outside the person's folder as stored" do
    File.binwrite(root.join("elsewhere.pdf"), "%PDF-1.4 elsewhere")
    person.update_columns(upload_medical_pdf: root.join("elsewhere.pdf").to_s)

    show_medical

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("%PDF-1.4 elsewhere")
  end

  it "does not find a document that is not there" do
    person.update_columns(upload_medical_pdf: folder.join("missing.pdf").to_s)

    show_medical

    expect(response).to have_http_status(:not_found)
  end
end
