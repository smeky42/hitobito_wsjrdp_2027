# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DocumentStore do
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:now) { Time.zone.local(2026, 10, 11, 14, 3, 7) }
  let(:pdf) { "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n".b }
  let(:png) { "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b + ("\x00" * 32).b }
  let(:folder) { root.join("person/pdf/#{person.id}") }

  before { allow(described_class).to receive(:root).and_return(root) }
  after { FileUtils.rm_rf(root) }

  def store(content = pdf, ext: nil, now: self.now, **attrs, &block)
    described_class.store!(StringIO.new(content), {subject: person, key: "medical", filename: "Scan.PDF"}.merge(attrs),
      ext: ext, now: now, &block)
  end

  def files = folder.children.map { |path| path.basename.to_s }.sort

  it "writes the file under its name and the row that names it" do
    document = store

    name = "2026-10-11-14-03-07--#{person.id}-medical.pdf"
    expect(files).to eq([name])
    expect(folder.join(name).binread).to eq(pdf)
    expect(document.reload).to have_attributes(
      status: "current", relative_storage_file_path: "person/pdf/#{person.id}/#{name}",
      absolute_storage_file_path: folder.join(name).to_s, filename: "Scan.PDF", content_type: "application/pdf",
      byte_size: pdf.bytesize, content_sha256: Digest::SHA256.hexdigest(pdf),
      file_status: "present", file_checked_at: be_present
    )
    expect(described_class.path_for(document)).to eq(folder.join(name))
  end

  it "takes the extension as given, else from the file name, else from the content type, else none" do
    expect(File.basename(store(ext: "pdf.gz").absolute_storage_file_path)).to end_with("-medical.pdf.gz")
    expect(File.basename(store(png, key: "photo", filename: "bild").absolute_storage_file_path))
      .to end_with("-photo.png")
    expect(File.basename(store("plain words".b * 3, key: "note", filename: "notiz", content_type: "text/plain")
      .absolute_storage_file_path)).to end_with("-note.txt")
    expect(File.basename(store("\x00\x01\x02".b, key: "blob", filename: "blob").absolute_storage_file_path))
      .to end_with("-blob")
  end

  it "refuses an invalid extension and invalid keys before writing" do
    expect { store(ext: "pdf.") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { store(key: "Medical") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { store(secondary_key: "page-2") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(files).to be_empty
    expect(WsjrdpDocument.of_subject(person)).to be_empty
  end

  it "refuses a second current document in a slot" do
    store

    expect { store(now: now + 1) }.to raise_error(ActiveRecord::RecordInvalid, /aktuelles Dokument/)
    expect(files.size).to eq(1)
  end

  describe "a replacement" do
    it "supersedes the document it replaces and takes its keys and lists" do
      old = store(key: "deregistration", key_number: 2, secondary_key: "signed_form",
        readable_by: %w[log finance], writable_by: %w[log])

      new = store(replaces: old, key: nil, filename: "neu.pdf", now: now + 60)

      expect(old.reload).to have_attributes(status: "superseded", superseded_at: be_present)
      expect(new).to have_attributes(key: "deregistration", key_number: 2, secondary_key: "signed_form",
        replaces_id: old.id, readable_by: %w[log finance], writable_by: %w[log], status: "current")
      expect(new.predecessors).to eq([old])
      expect(WsjrdpDocument.current_for(person, key: "deregistration", key_number: 2, secondary_key: "signed_form"))
        .to eq(new)
    end

    it "in the same second gets the next suffix" do
      old = store

      new = store(replaces: old)

      expect(File.basename(new.absolute_storage_file_path)).to eq("2026-10-11-14-03-07_1--#{person.id}-medical.pdf")
      expect(files.size).to eq(2)
    end

    it "is refused when the document is no longer current" do
      old = store
      store(replaces: old, now: now + 1)

      expect { store(replaces: old.reload, now: now + 2) }.to raise_error(ActiveRecord::RecordInvalid, /nicht mehr aktuell/)
      expect(files.size).to eq(2)
    end

    it "is followed by a document prepared without replaces, which takes its lists unless given" do
      old = store(readable_by: %w[log finance], writable_by: %w[log])
      store = described_class.new
      attributes = {subject: person, key: "medical", filename: "neu.pdf"}

      prepared = store.prepare(StringIO.new(pdf), attributes, ext: nil, upload: true, follow_current: true)
      expect(prepared.document).to have_attributes(replaces: old, readable_by: %w[log finance], writable_by: %w[log])

      store.follow(prepared, nil)
      expect(prepared.document).to have_attributes(replaces: nil, readable_by: %w[person update], writable_by: %w[log])

      given = store.prepare(StringIO.new(pdf), attributes.merge(readable_by: %w[person]), ext: nil, upload: true,
        follow_current: true)
      expect(given.document).to have_attributes(replaces: old, readable_by: %w[person], writable_by: %w[log])
    end
  end

  it "never overwrites a file without a row" do
    FileUtils.mkdir_p(folder)
    taken = folder.join("2026-10-11-14-03-07--#{person.id}-medical.pdf")
    taken.write("other")

    document = store

    expect(taken.read).to eq("other")
    expect(File.basename(document.absolute_storage_file_path)).to eq("2026-10-11-14-03-07_1--#{person.id}-medical.pdf")
  end

  it "fills the file in exclusively where there are no hard links" do
    allow(File).to receive(:link).and_raise(Errno::EPERM)

    document = store

    expect(Pathname(document.absolute_storage_file_path).binread).to eq(pdf)
    expect(files.size).to eq(1)
  end

  it "stores a derivation with its own name, subject and keys of its original" do
    original = store(key: "deregistration", secondary_key: "letter", filename: "brief.eml")

    derivation = store(png, key: nil, subject: nil, derived_from: original, derivation_key: "thumb_400",
      filename: "thumb.png", now: now + 5)

    expect(derivation).to have_attributes(subject: person, key: "deregistration", secondary_key: "letter",
      derived_from_id: original.id, derivation_key: "thumb_400")
    expect(File.basename(derivation.absolute_storage_file_path))
      .to eq("2026-10-11-14-03-12--#{person.id}-deregistration--letter~thumb_400.png")
  end

  it "refuses an upload above the limit and leaves nothing behind" do
    allow(described_class).to receive(:max_upload_size).and_return(10)

    expect { store }.to raise_error(described_class::TooLarge)
    expect(files).to be_empty
    expect(WsjrdpDocument.of_subject(person)).to be_empty
  end

  it "has no limit for what is not an upload" do
    allow(described_class).to receive(:max_upload_size).and_return(10)

    expect { described_class.store!(StringIO.new(pdf), {subject: person, key: "medical", filename: "a.pdf"}, upload: false) }
      .not_to raise_error
  end

  it "writes nothing when the block refuses" do
    expect { store { raise CanCan::AccessDenied } }.to raise_error(CanCan::AccessDenied)
    expect(folder).not_to exist
  end

  it "stores the document of a person whose data is not valid and logs the warning" do
    person.update_columns(language: "xx")
    allow(Rails.logger).to receive(:warn)

    document = store

    expect(person.reload.upload_medical_pdf).to eq(document.absolute_storage_file_path)
    expect(Rails.logger).to have_received(:warn).with(a_string_including("nicht gültig"))
  end

  it "hides a document and keeps its file" do
    document = store

    described_class.hide!(document, reason: "test")

    expect(document.reload).to have_attributes(status: "deleted", deleted_at: be_present)
    expect(document.additional_info).to include("deleted_reason" => "test")
    expect(Pathname(document.absolute_storage_file_path)).to exist
  end

  it "hides a document whose subject is gone" do
    document = store
    document.update_columns(subject_id: 0)

    described_class.hide!(document.reload, reason: "gone")

    expect(document.reload).to have_attributes(status: "deleted", subject: nil)
  end

  it "hides the current document of a slot, if there is one" do
    document = store

    expect(described_class.hide_current!(person, reason: "x", by: people(:cmt_leader), key: "medical"))
      .to eq(document)
    expect(document.reload).to have_attributes(status: "deleted")
    expect(document.additional_info).to include("deleted_by_id" => people(:cmt_leader).id)
    expect(described_class.hide_current!(person, key: "medical")).to be_nil
  end

  describe "of a kind" do
    it "takes the kind's rights unless given" do
      expect(store).to have_attributes(readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log])
      expect(store(key: "sepa", readable_by: %w[log])).to have_attributes(readable_by: %w[log],
        writable_by: %w[log])
      expect(store(key: "letter")).to have_attributes(readable_by: %w[person log], writable_by: %w[person log])
      expect(store(key: "note")).to have_attributes(readable_by: %w[log], writable_by: [], deletable_by: [])
    end

    it "refuses an upload the kind does not accept and leaves nothing behind" do
      expect { store(png, filename: "bild.png") }.to raise_error(ActiveRecord::RecordInvalid) { |e|
        expect(e.record.errors.details[:base]).to include(a_hash_including(error: :kind_content_type))
      }
      expect { store(filename: "scan") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(files).to be_empty
    end

    it "applies the kind's size limit" do
      wsjrdp_document_kinds(:medical).update!(max_upload_size_mb: 1)

      expect { store(pdf + ("x" * 1.megabyte).b) }.to raise_error(described_class::TooLarge) { |e|
        expect(e.limit_mb).to eq(1)
      }
    end

    it "checks nothing for what is not an upload" do
      expect(described_class.store!(StringIO.new(png), {subject: person, key: "medical", filename: "bild.png"},
        upload: false)).to be_persisted
    end
  end

  describe ".register!" do
    let(:path) { folder.join("2026-10-11-14-03-07--#{person.id}-medical.pdf") }

    before do
      FileUtils.mkdir_p(folder)
      path.binwrite(pdf)
    end

    it "registers a file in place and replaces the current document of the slot" do
      old = store(now: now - 1.day)

      document = described_class.register!(path, {subject: person, key: "medical", origin: "registration_upload"},
        now: now)

      expect(document).to have_attributes(persisted?: true, relative_storage_file_path: path.relative_path_from(root).to_s,
        filename: path.basename.to_s, byte_size: pdf.bytesize, content_type: "application/pdf",
        file_status: "present", readable_by: %w[person update], replaces: old, created_at: now)
      expect(old.reload.status).to eq("superseded")
    end

    it "marks a file that is not there missing" do
      path.delete

      document = described_class.register!(path, {subject: person, key: "medical"})

      expect(document).to have_attributes(file_status: "missing", content_type: "application/pdf", byte_size: nil)
    end

    it "refuses a path outside the root" do
      expect { described_class.register!("/etc/passwd", {subject: person, key: "medical"}) }
        .to raise_error(ArgumentError)
    end
  end

  it "refuses relative paths that leave the root" do
    ["../x.pdf", "/etc/passwd", "person/../../x", ""].each do |path|
      expect { described_class.path_for(WsjrdpDocument.new(relative_storage_file_path: path)) }
        .to raise_error(ArgumentError), path
    end
  end

  it "defaults to the upload root of the registration uploads" do
    allow(described_class).to receive(:root).and_call_original
    allow(Settings.documents).to receive(:storage_root).and_return(nil)

    expect(described_class.root).to eq(HitobitoWsjrdp2027::Wagon.root.join("private", "uploads"))
  end

  it "keeps the specs out of the wagon's upload root" do
    allow(described_class).to receive(:root).and_call_original

    expect(described_class.root.to_s).to start_with(Dir.tmpdir)
  end
end
