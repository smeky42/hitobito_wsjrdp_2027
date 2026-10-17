# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::RegistrationDocuments do
  let(:person) { people(:yp_a_1) }
  let(:uploader) { people(:cmt_leader) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:folder) { root.join("person/pdf/#{person.id}") }
  let(:prefix) { "/app-src/vendor/wagons/hitobito_wsjrdp_2027/private/uploads/person/pdf/#{person.id}" }
  let(:first) { "2025-06-28-14-38-32--#{person.id}-medical.pdf" }
  let(:second) { "2025-10-09-22-36-30--#{person.id}-medical.pdf" }

  before { allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root) }
  after { FileUtils.rm_rf(root) }

  def file(name, content = "%PDF-1.4 #{name}")
    FileUtils.mkdir_p(folder)
    folder.join(name).write(content)
  end

  # A version as the upload page leaves it: the column from one path to the
  # next, by whom and when.
  def version(column, from, to, at, by: uploader)
    yaml = {column => [from && "#{prefix}/#{from}", to && "#{prefix}/#{to}"]}.to_yaml
    PaperTrail::Version.create!(item_type: "Person", item_id: person.id, main_type: "Person", main_id: person.id,
      event: "update", whodunnit: by&.id&.to_s, whodunnit_type: by && "Person", object_changes: yaml, created_at: at)
  end

  def scan = described_class::Scan.new(person_ids: [person.id]).run

  def chain(key = "medical") = scan.chain(person.id, key)

  def register(chains = [chain]) = described_class::Import.new.register(chains)

  def documents = WsjrdpDocument.of_subject(person).order(:created_at, :id).to_a

  context "with an upload, a replacement and the column on the replacement" do
    before do
      file(first)
      file(second)
      version("upload_medical_pdf", nil, first, Time.zone.local(2025, 6, 28, 14, 38, 33))
      version("upload_medical_pdf", first, second, Time.zone.local(2025, 10, 9, 22, 36, 31))
      person.update_columns(upload_medical_pdf: "#{prefix}/#{second}")
    end

    it "makes one chain, oldest first, the column's file current" do
      expect(chain.entries.map(&:filename)).to eq([first, second])
      expect(chain.entries.map(&:status)).to eq(%w[superseded current])
      expect(chain.entries.first.superseded_at).to eq(chain.entries.last.set_at)
      expect(chain.entries.map(&:author_id)).to eq([uploader.id, uploader.id])
      expect(chain.state).to eq(:new)
    end

    it "registers the chain where the files lie, each replacing the one before" do
      result = register

      expect(result.to_h).to include(chains: 1, created: 2, updated: 0, failed: 0)
      old, current = documents
      expect(old).to have_attributes(key: "medical", status: "superseded", origin: "import", filename: first,
        relative_storage_file_path: "person/pdf/#{person.id}/#{first}",
        absolute_storage_file_path: "#{prefix}/#{first}", author: uploader, file_status: "present",
        content_sha256: Digest::SHA256.hexdigest(folder.join(first).read), byte_size: folder.join(first).size,
        readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log])
      expect(old.created_at).to eq(Time.zone.local(2025, 6, 28, 14, 38, 33))
      expect(current).to have_attributes(status: "current", replaces_id: old.id, filename: second)
      expect(current.additional_info["registration_upload"]).to include("column" => "upload_medical_pdf",
        "source" => "version")
      expect(chain.state).to eq(:complete)
      expect(person.reload.upload_medical_pdf).to eq("#{prefix}/#{second}")
    end

    it "changes nothing when run again" do
      register

      expect(register.to_h).to include(created: 0, updated: 0)
      expect(documents.size).to eq(2)
    end

    it "appends a later upload and supersedes the one before" do
      register
      third = "2026-01-02-10-00-00--#{person.id}-medical.pdf"
      file(third)
      version("upload_medical_pdf", second, third, Time.zone.local(2026, 1, 2, 10, 0, 1))
      person.update_columns(upload_medical_pdf: "#{prefix}/#{third}")

      expect(chain.state).to eq(:partial)
      expect(register.to_h).to include(created: 1, updated: 1)
      expect(documents.map(&:status)).to eq(%w[superseded superseded current])
      expect(documents.last.replaces_id).to eq(documents.second.id)
    end

    it "gives the rows the rights of their kind, else the table's defaults" do
      wsjrdp_document_kinds(:medical).update!(readable_by: %w[log finance])
      register

      expect(documents.map(&:readable_by).uniq).to eq([%w[log finance]])

      WsjrdpDocument.delete_all
      wsjrdp_document_kinds(:medical).destroy!
      register
      expect(documents.map(&:readable_by).uniq).to eq([%w[log]])
      expect(documents.map(&:deletable_by).uniq).to eq([[]])
    end
  end

  it "registers a missing file as a row without file and deletes after emptying the column" do
    file(second)
    version("upload_medical_pdf", nil, first, Time.zone.local(2025, 6, 28, 14, 38, 33))
    version("upload_medical_pdf", first, second, Time.zone.local(2025, 10, 9, 22, 36, 31))
    version("upload_medical_pdf", second, nil, Time.zone.local(2025, 11, 1, 9, 0, 0), by: people(:admin))

    expect(chain.entries.map(&:exists)).to eq([false, true])
    register

    missing, deleted = documents
    expect(missing).to have_attributes(file_status: "missing", byte_size: nil, content_sha256: nil,
      status: "superseded")
    expect(deleted).to have_attributes(status: "deleted", deleted_at: Time.zone.local(2025, 11, 1, 9, 0, 0))
    expect(deleted.additional_info["registration_upload"]["cleared_by"]).to eq("type" => "Person",
      "id" => people(:admin).id)
  end

  it "clears the times of a document that is current again" do
    file(first)
    register
    expect(documents.sole).to have_attributes(status: "deleted", superseded_at: nil)
    expect(documents.sole.deleted_at).to be_present

    version("upload_medical_pdf", nil, first, Time.zone.local(2025, 6, 28, 14, 38, 33))
    person.update_columns(upload_medical_pdf: "#{prefix}/#{first}")
    register
    expect(documents.sole).to have_attributes(status: "current", deleted_at: nil, superseded_at: nil)
  end

  it "makes one chain of an older generated registration PDF named with a dash and a newer one" do
    older = "2025-06-28-14-38-32--#{person.id}-registration-generated.pdf"
    newer = described_class.generated_registration_filename(person, at: Time.zone.local(2026, 10, 17, 10, 15))
    file(older)
    file(newer)
    version("generated_registration_pdf", nil, older, Time.zone.local(2025, 6, 28, 14, 38, 33))
    version("generated_registration_pdf", older, newer, Time.zone.local(2026, 10, 17, 10, 15, 1))
    person.update_columns(generated_registration_pdf: "#{prefix}/#{newer}")

    chain = scan.chain(person.id, "registration_generated")
    expect(chain.entries.map(&:filename)).to eq([older, newer])
    expect(chain.entries.map(&:status)).to eq(%w[superseded current])
    register([chain])
    expect(documents.map(&:key).uniq).to eq(["registration_generated"])
    expect(documents.last.replaces_id).to eq(documents.first.id)
  end

  it "checks a registered file again on every run: missing, back with its data, gone again" do
    version("upload_medical_pdf", nil, first, Time.zone.local(2025, 6, 28, 14, 38, 33))
    register
    expect(documents.first).to have_attributes(file_status: "missing", byte_size: nil, content_sha256: nil)
    expect(chain.state).to eq(:complete)

    file(first, "%PDF-1.4 back")
    expect(chain.state).to eq(:partial)
    later = 1.hour.from_now.change(usec: 0)
    result = described_class::Import.new(now: later).register([chain])
    expect(result.updated).to eq(1)
    expect(documents.first).to have_attributes(file_status: "present", byte_size: 13, file_checked_at: later,
      content_sha256: Digest::SHA256.hexdigest("%PDF-1.4 back"), content_type: "application/pdf")

    # Nothing changed: only the time of the check moves on.
    again = 2.hours.from_now.change(usec: 0)
    expect(described_class::Import.new(now: again).register([chain]).updated).to eq(0)
    expect(documents.first.file_checked_at).to eq(again)

    folder.join(first).delete
    expect(chain.state).to eq(:partial)
    register
    expect(documents.first).to have_attributes(file_status: "missing", byte_size: 13)
  end

  it "notes the complete chains of a run as checked" do
    file(first)
    version("upload_medical_pdf", nil, first, Time.zone.local(2025, 6, 28, 14, 38, 33))
    register
    later = 1.hour.from_now.change(usec: 0)

    described_class::Import.new(now: later).checked([chain])
    expect(documents.first.file_checked_at).to eq(later)
  end

  it "takes a file without a version by the time of its name, and the column's file without one" do
    file(first)
    file(second)
    person.update_columns(upload_medical_pdf: "#{prefix}/#{second}")

    expect(chain.entries.map { |entry| [entry.filename, entry.source, entry.status] })
      .to eq([[first, :disk, "superseded"], [second, :column, "current"]])
  end

  it "lists what it cannot place and leaves documents of the new storage alone" do
    file("notes.pdf")
    file("2026-10-11-14-03-07--#{person.id}-medical.pdf.tmp")
    stored = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
      {subject: person, key: "deregistration", filename: "a.pdf"})

    found = scan
    expect(found.anomalies.map { |anomaly| [anomaly.kind, File.basename(anomaly.path)] })
      .to contain_exactly([:unexpected_name, "notes.pdf"], [:unexpected_name, "2026-10-11-14-03-07--#{person.id}-medical.pdf.tmp"])
    expect(found.chains.map(&:key)).not_to include("deregistration")
    expect(stored).to be_persisted
  end

  it "reads every column of a version in one pass, plain, quoted or escaped" do
    yaml = "---\nupload_sepa_pdf:\n- /x/a.pdf\n- \"/x/b c.pdf\"\nfirst_name:\n- A\n- B\n" \
      "generated_registration_pdf:\n- ~\n- \"/x/\\u00e4.pdf\"\n"
    expect(described_class::Scan.column_changes(yaml)).to eq(
      "upload_sepa_pdf" => ["/x/a.pdf", "/x/b c.pdf"], "generated_registration_pdf" => [nil, "/x/ä.pdf"]
    )
  end

  it "notices a temporary file left in a folder" do
    file(".tmp-0123456789abcdef")

    expect(scan.anomalies.map(&:kind)).to include(:temporary_file)
  end

  it "reads the paths of a version's YAML in every form" do
    yaml = "---\nupload_sepa_pdf:\n-\n- \"/x/private/uploads/person/pdf/1/a.pdf\"\nother: 1\n"
    expect(described_class::Scan.column_change(yaml, "upload_sepa_pdf"))
      .to eq([nil, "/x/private/uploads/person/pdf/1/a.pdf"])
    expect(described_class::Scan.column_change(yaml, "upload_medical_pdf")).to be_nil
  end

  it "writes durations as a person reads them" do
    format = ->(seconds) { Wsjrdp2027::RegisterDocumentsJob.format_duration(seconds) }

    expect([0.85, 12.34, 252, 3780].map(&format)).to eq(["850 ms", "12,3 s", "4 min 12 s", "1 h 3 min"])
  end
  it "names a new generated registration PDF with its key, read back without the legacy mapping" do
    name = described_class.generated_registration_filename(person, at: Time.zone.local(2026, 10, 17, 10, 15))
    expect(name).to eq("2026-10-17-10-15-00--#{person.id}-registration_generated.pdf")
    expect(Wsjrdp2027::DocumentFilename.parse(name)).to include(key: "registration_generated", subject_id: person.id)

    file(name)
    person.update_columns(generated_registration_pdf: "#{prefix}/#{name}")
    chain = scan.chain(person.id, "registration_generated")
    expect(chain.entries.map(&:filename)).to eq([name])
    expect(chain.entries.first).to have_attributes(status: "current", exists: true,
      set_at: Time.zone.local(2026, 10, 17, 10, 15))
  end

  it "reads the legacy name of the generated registration PDF as the key registration_generated" do
    name = "2025-06-28-14-38-32--#{person.id}-registration-generated.pdf"
    file(name)
    person.update_columns(generated_registration_pdf: "#{prefix}/#{name}")

    chain = scan.chain(person.id, "registration_generated")
    expect(chain.entries.map(&:filename)).to eq([name])
    expect(chain.entries.first).to have_attributes(status: "current", exists: true,
      set_at: Time.zone.local(2025, 6, 28, 14, 38, 32))
    expect(scan.anomalies).to be_empty

    register([chain])
    expect(documents.sole).to have_attributes(key: "registration_generated", filename: name)
  end

  describe "keeping wsjrdp_documents in step with a column" do
    it "maps columns and keys" do
      expect(described_class.key_for(:upload_sepa_pdf)).to eq("sepa")
      expect(described_class.people_column_for("registration_generated")).to eq("generated_registration_pdf")
      expect { described_class.key_for("first_name") }.to raise_error(KeyError)
      expect { described_class.people_column_for("letter") }.to raise_error(KeyError)
    end

    it "records the file a column was set to as the current document of its key" do
      file(first)
      file(second)

      old = described_class.record!(person, people_column: "upload_medical_pdf", path: "#{prefix}/#{first}",
        author: uploader, origin: "upload")
      current = described_class.record!(person, people_column: "upload_medical_pdf", path: "#{prefix}/#{second}")

      expect(old.reload).to have_attributes(status: "superseded", author: uploader, origin: "upload",
        readable_by: %w[person update], relative_storage_file_path: "person/pdf/#{person.id}/#{first}")
      expect(old.additional_info["registration_upload"]).to eq("column" => "upload_medical_pdf", "source" => "upload")
      expect(current).to have_attributes(status: "current", replaces_id: old.id, key: "medical", file_status: "present")
      expect(described_class.record!(person, people_column: "upload_medical_pdf", path: "#{prefix}/#{second}"))
        .to eq(current)
      person.update_columns(upload_medical_pdf: "#{prefix}/#{second}")
      expect(chain.state).to eq(:complete)
    end

    it "hides the current document of a column that was emptied" do
      file(first)
      document = described_class.record!(person, people_column: "upload_medical_pdf", path: "#{prefix}/#{first}")

      expect(described_class.clear!(person, people_column: "upload_medical_pdf", by: uploader)).to eq(document)
      expect(document.reload).to have_attributes(status: "deleted")
      expect(document.additional_info).to include("deleted_reason" => "column_cleared", "deleted_by_id" => uploader.id)
      expect(described_class.clear!(person, people_column: "upload_medical_pdf")).to be_nil
    end

    it "refuses a path outside the upload root" do
      expect { described_class.record!(person, people_column: "upload_medical_pdf", path: "/etc/passwd") }
        .to raise_error(ArgumentError)
    end
  end
end
