# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe DocumentManagement::DocumentsHelper, type: :helper do
  def cell(content_type) = Capybara.string(helper.document_type_cell(content_type).to_s)

  describe "#document_type_cell" do
    it "shows the icon and short name of a known type, the type as tooltip" do
      html = cell("application/pdf")

      expect(html).to have_css("span[title='PDF – application/pdf'] i.fa-file-pdf")
      expect(html).to have_css("span.text-truncate", text: "PDF")
      expect(html).to have_no_css(".text-muted")
    end

    it "shows an unknown type muted, with its subtype" do
      html = cell("multipart/appledouble")

      expect(html).to have_css("span.text-muted[title='multipart/appledouble'] i.fa-file")
      expect(html).to have_css("span.text-truncate", text: "appledouble")
    end

    it "stays empty without a type" do
      expect(helper.document_type_cell("")).to be_nil
      expect(helper.document_type_cell(nil)).to be_nil
    end
  end

  it "shows the type the same way in the versions table" do
    columns = helper.document_version_table_columns([nil, nil], "p", people: {}, with_numbers: false)
    type = columns.find { |col| col[:key] == "content_type" }

    expect(type[:cell].call(WsjrdpDocument.new(content_type: "image/png")).to_s).to include("PNG", "fa-file-image")
  end
end
