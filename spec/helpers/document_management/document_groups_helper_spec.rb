# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe DocumentManagement::DocumentGroupsHelper, type: :helper do
  def group(key, kind: nil, secondary_key: "")
    DocumentManagement::DocumentGroups::Group.new(subject_type: "Person", subject_id: 42, key: key,
      secondary_key: secondary_key, kind: kind)
  end

  def filter_of(path) = CGI.unescape(path)

  it "links a group to the tab Alle by person and kind" do
    path = filter_of(helper.document_group_documents_path(group("medical", kind: wsjrdp_document_kinds(:medical))))

    expect(path).to start_with("/documents?")
    expect(path).to include("(kd,in,'medical')").and include("(sid,in,'42')")
    expect(path).not_to include("(k,in,")
  end

  it "links a group without a kind by its keys" do
    path = filter_of(helper.document_group_documents_path(group("deregistration")))

    expect(path).to include("(k,in,'deregistration')")
    expect(path).not_to include("(kd,in,")
  end

  it "names a kind with a secondary key by both keys" do
    expect(WsjrdpDocumentKind.new(key: "deregistration", secondary_key: "signed_form").keys_path)
      .to eq("deregistration/signed_form")
    expect(wsjrdp_document_kinds(:medical).keys_path).to eq("medical")
  end
end
