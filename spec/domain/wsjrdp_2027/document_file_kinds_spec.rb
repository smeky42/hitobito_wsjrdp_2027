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

  it "gives a type the icon of its file kind and a short name" do
    expect(described_class.icon_for("application/pdf")).to eq(:"file-pdf")
    expect(described_class.icon_for("image/jpeg")).to eq(:"file-image")
    expect(described_class.icon_for("application/vnd.openxmlformats-officedocument.wordprocessingml.document"))
      .to eq(:"file-word")
    expect(described_class.icon_for("message/rfc822")).to eq(:envelope)
    expect(described_class.icon_for("application/gzip")).to eq(:"file-archive")
    expect(described_class.short_label_for("application/pdf")).to eq("PDF")
    expect(described_class.short_label_for("application/msword")).to eq("Word")
  end

  it "has a generic icon and no short name for another type" do
    expect(described_class.icon_for("image/tiff")).to eq(:"file-image")
    expect(described_class.icon_for("text/csv")).to eq(:"file-alt")
    expect(described_class.icon_for("multipart/appledouble")).to eq(:file)
    expect(described_class.icon_for(nil)).to eq(:file)
    expect(described_class.short_label_for("multipart/appledouble")).to be_nil
  end

  it "has a short name for every type it names" do
    expect(described_class::TYPE_LABELS.keys - described_class::SHORT_LABELS.keys).to be_empty
  end

  it "has only extensions a kind of document accepts" do
    extensions = described_class::LIST.flat_map { |kind| kind[:extensions] }
    expect(extensions).to all(match(WsjrdpDocumentKind::EXTENSION_FORMAT))
    expect(extensions).to eq(extensions.uniq)
  end
end
