# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DocumentFileCheck do
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:now) { 1.hour.from_now.change(usec: 0) }

  before { allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root) }

  after { FileUtils.rm_rf(root) }

  # Each in a slot of its own (one current document per slot).
  def store(name)
    @number = @number.to_i + 1
    Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 #{name}"),
      {subject: person, key: "deregistration", key_number: @number, filename: "#{name}.pdf"})
  end

  def check = described_class.new(now: now).tap { |check| check.check(described_class.rows) }

  it "marks a file that is gone missing, one that is back present with its data, and stamps every row" do
    kept, gone, back = store("kept"), store("gone"), store("back")
    Wsjrdp2027::DocumentStore.path_for(gone).delete
    back.update_columns(file_status: "missing", byte_size: nil, content_sha256: nil)

    result = check.result

    expect(result.to_h).to include(checked: 3, missing: 1, back: 1, failed: 0)
    expect(gone.reload).to have_attributes(file_status: "missing", file_checked_at: now)
    expect(back.reload).to have_attributes(file_status: "present", file_checked_at: now,
      byte_size: "%PDF-1.4 back".bytesize, content_sha256: Digest::SHA256.hexdigest("%PDF-1.4 back"),
      content_type: "application/pdf")
    expect(kept.reload).to have_attributes(file_status: "present", file_checked_at: now)
  end

  it "counts a row with an empty path, or with one the store refuses, as missing" do
    blank, outside = store("blank"), store("outside")
    blank.update_columns(relative_storage_file_path: "")
    outside.update_columns(relative_storage_file_path: "../elsewhere.pdf")

    expect(check.result.missing).to eq(2)
    expect([blank.reload.file_status, outside.reload.file_status]).to eq(%w[missing missing])
  end

  it "keeps the type a row has when its file comes back" do
    document = store("typed")
    document.update_columns(file_status: "missing", content_type: "application/x-kept")

    check
    expect(document.reload).to have_attributes(file_status: "present", content_type: "application/x-kept")
  end
end
