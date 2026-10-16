# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DocumentFileKinds do
  def kind(key) = described_class.all.find { |kind| kind[:key] == key }

  it "takes the types from Marcel" do
    expect(kind("word_processing")[:types]).to include("application/msword",
      "application/vnd.oasis.opendocument.text-template")
    expect(kind("plain_text")[:types]).to eq(%w[text/plain text/markdown])
  end

  it "names the types of compound archive extensions, never the unknown type" do
    expect(kind("archives")[:types]).to eq(%w[application/zip application/x-tar application/gzip
      application/x-bzip2 application/zstd])
    expect(described_class.type_for("tar.zst")).to eq("application/zstd")
    expect(described_class.type_for("nothing-known")).to be_nil
  end

  it "groups the extensions by their type, for the tooltips" do
    expect(kind("spreadsheets")[:groups].first).to eq(type: "application/vnd.ms-excel",
      label: "Excel 97–2003, auch Vorlage", extensions: %w[xls xlt])
    expect(described_class.all.flat_map { |kind| kind[:groups] }.pluck(:label)).to all(be_present)
  end

  it "has only extensions a kind of document accepts" do
    extensions = described_class::LIST.flat_map { |kind| kind[:extensions] }
    expect(extensions).to all(match(WsjrdpDocumentKind::EXTENSION_FORMAT))
    expect(extensions).to eq(extensions.uniq)
  end
end
