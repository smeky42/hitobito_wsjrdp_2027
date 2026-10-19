# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Two writes at once: document_write_concurrency_spec.
describe Wsjrdp2027::DocumentWrite do
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:now) { Time.zone.local(2026, 10, 11, 14, 3, 7) }
  let(:folder) { root.join("person/pdf/#{person.id}") }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    person.update_columns(upload_medical_pdf: nil, upload_sepa_pdf: nil)
  end

  after { FileUtils.rm_rf(root) }

  def pdf(text = "a") = "%PDF-1.4\n#{text}\n%%EOF\n"

  def write(**options) = described_class.new(subject: person, by: people(:cmt_leader), origin: "ui", **options)

  def put_file(write, key, content = pdf, **options)
    write.put(StringIO.new(content), {key: key, filename: "#{key}.pdf"}, now: now, **options)
  end

  def files = folder.exist? ? folder.children.map { |path| path.basename.to_s }.sort : []

  def statements
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  it "stores the document and writes its path into the people column of its kind" do
    result = put_file(write, "medical").commit!.first

    expect(result.outcome).to eq(described_class::STORED)
    expect(result.document).to have_attributes(persisted?: true, status: "current", author: people(:cmt_leader),
      origin: "ui")
    expect(person.reload.upload_medical_pdf).to eq(result.document.absolute_storage_file_path)
  end

  it "replaces the current document and keeps the column on the new one" do
    old = put_file(write, "medical", pdf("old")).commit!.first.document

    new = put_file(write, "medical", pdf("new"), now: now + 60).commit!.first.document

    expect(old.reload.status).to eq("superseded")
    expect(new.replaces).to eq(old)
    expect(person.reload.upload_medical_pdf).to eq(new.absolute_storage_file_path)
  end

  it "adds nothing for the file the slot already has" do
    current = put_file(write, "medical").commit!.first.document

    result = put_file(write, "medical", now: now + 60).commit!.first

    expect(result).to have_attributes(outcome: described_class::UNCHANGED, document: current)
    expect(WsjrdpDocument.of_subject(person).count).to eq(1)
    expect(files.size).to eq(1)
  end

  it "stores the same file again without skip_unchanged" do
    put_file(write, "medical").commit!

    expect(put_file(write(skip_unchanged: false), "medical", now: now + 60).commit!.first.outcome)
      .to eq(described_class::STORED)
  end

  it "follows the current document and takes its lists unless given" do
    old = write.put(StringIO.new(pdf("old")), {key: "medical", filename: "alt.pdf", readable_by: %w[log finance]},
      now: now).commit!.first.document

    new = put_file(write, "medical", pdf("new"), now: now + 1).commit!.first.document
    given = write.put(StringIO.new(pdf("given")), {key: "medical", filename: "neu.pdf", readable_by: %w[person]},
      now: now + 2).commit!.first.document

    expect(new).to have_attributes(replaces_id: old.id, readable_by: %w[log finance], writable_by: %w[log])
    expect(given).to have_attributes(replaces_id: new.id, readable_by: %w[person], writable_by: %w[log])
    expect(old.reload.status).to eq("superseded")
  end

  it "removes the current document and empties the column" do
    document = put_file(write, "medical").commit!.first.document

    result = write.remove(key: "medical", reason: "deleted_by_user").commit!.first

    expect(result).to have_attributes(outcome: described_class::REMOVED, document: document)
    expect(document.reload).to have_attributes(status: "deleted", deleted_at: be_present)
    expect(document.additional_info).to include("deleted_reason" => "deleted_by_user",
      "deleted_by_id" => people(:cmt_leader).id)
    expect(person.reload.upload_medical_pdf).to be_nil
    expect(Pathname(document.absolute_storage_file_path)).to exist
  end

  it "has nothing to remove in a free slot" do
    expect(write.remove(key: "medical").commit!.first.outcome).to eq(described_class::NOT_PRESENT)
  end

  describe "expected_current" do
    let!(:current) { put_file(write, "medical", pdf("current")).commit!.first.document }

    it "is the document to replace" do
      result = put_file(write, "medical", pdf("next"), now: now + 1, expected_current: current.id).commit!.first

      expect(result.document.replaces).to eq(current)
    end

    it "refuses a write that expects a free slot" do
      expect { put_file(write, "medical", pdf("next"), expected_current: nil).commit! }
        .to raise_error(ActiveRecord::RecordInvalid) { |e|
          expect(e.record.errors.details[:base]).to include(a_hash_including(error: :slot_taken))
        }
    end

    it "refuses a write that expects another document" do
      put_file(write, "medical", pdf("between"), now: now + 1).commit!

      expect { put_file(write, "medical", pdf("next"), now: now + 2, expected_current: current).commit! }
        .to raise_error(ActiveRecord::RecordInvalid, /nicht mehr aktuell/)
      expect(files.size).to eq(2)
    end

    it "refuses a removal of another document" do
      expect { write.remove(key: "medical", expected_current: current.id + 1).commit! }
        .to raise_error(described_class::Conflict)
      expect(current.reload.status).to eq("current")
    end
  end

  describe "several files" do
    it "stores all of them in one change" do
      results = put_file(put_file(write, "medical"), "sepa").commit!

      expect(results.map(&:outcome)).to eq([described_class::STORED] * 2)
      expect(person.reload).to have_attributes(upload_medical_pdf: results.first.document.absolute_storage_file_path,
        upload_sepa_pdf: results.last.document.absolute_storage_file_path)
    end

    it "stores none when one is refused" do
      change = put_file(write, "medical")
      change.put(StringIO.new("\x89PNG\r\n\x1A\n".b), {key: "sepa", filename: "bild.png"}, now: now)

      expect { change.commit! }.to raise_error(described_class::Invalid) { |e|
        expect(e.failures.size).to eq(1)
        expect(e.failures.first.first).to include(key: "sepa")
      }
      expect(files).to be_empty
      expect(WsjrdpDocument.of_subject(person)).to be_empty
      expect(person.reload.upload_medical_pdf).to be_nil
    end

    it "with skip_refused stores the others and names the refused one" do
      change = put_file(write(skip_refused: true), "medical")
      change.put(StringIO.new("\x89PNG\r\n\x1A\n".b), {key: "sepa", filename: "bild.png"}, now: now)

      results = change.commit!

      expect(results.map { |result| result.document.key }).to eq(%w[medical])
      expect(change.skipped.map { |attributes, error| [attributes[:key], error.class] })
        .to eq([["sepa", ActiveRecord::RecordInvalid]])
      expect(person.reload).to have_attributes(upload_medical_pdf: be_present, upload_sepa_pdf: nil)
      expect(files.size).to eq(1)
    end

    it "with skip_refused leaves out an empty file" do
      change = put_file(write(skip_refused: true), "medical")
      change.put(StringIO.new(""), {key: "sepa", filename: "leer.pdf"}, now: now)

      expect(change.commit!.map { |result| result.document.key }).to eq(%w[medical])
      expect(change.skipped.map { |attributes, error| [attributes[:key], error.record.errors.details[:base]] })
        .to eq([["sepa", [{error: :empty_file}]]])
    end

    it "with skip_refused answers nothing when every put is refused" do
      change = write(skip_refused: true)
      change.put(StringIO.new("\x89PNG\r\n\x1A\n".b), {key: "sepa", filename: "bild.png"}, now: now)

      expect(change.commit!).to eq([])
      expect(change.skipped.size).to eq(1)
      expect(WsjrdpDocument.of_subject(person)).to be_empty
      expect(files).to be_empty
    end

    it "keeps nothing when a later step fails" do
      change = put_file(write, "medical").on_subject { raise "boom" }

      expect { change.commit! }.to raise_error("boom")
      expect(files).to be_empty
      expect(WsjrdpDocument.of_subject(person)).to be_empty
      expect(person.reload.upload_medical_pdf).to be_nil
    end
  end

  describe "on_subject" do
    it "sees the locked subject with the columns written and saves what it changes" do
      put_file(write, "sepa").commit!
      Person.where(id: person.id).update_all(nickname: "Anderswo")
      seen = nil

      put_file(write, "medical").on_subject { |subject, results|
        seen = [subject.nickname, subject.upload_sepa_pdf.present?, subject.upload_medical_pdf.present?,
          results.map(&:outcome)]
        subject.status = "upload"
      }.commit!

      expect(seen).to eq(["Anderswo", true, true, [described_class::STORED]])
      expect(person.reload.status).to eq("upload")
    end

    it "answers RolledBack for a block that raises ActiveRecord::Rollback, leaving nothing behind" do
      change = put_file(write, "medical").on_subject { |*| raise ActiveRecord::Rollback }

      expect { change.commit! }.to raise_error(described_class::RolledBack)
      expect(WsjrdpDocument.of_subject(person)).to be_empty
      expect(files).to eq([])
      expect(person.reload.upload_medical_pdf).to be_nil
    end

    it "writes the version of the subject with the documents", versioning: true do
      expect { put_file(write, "medical").commit! }.to change { person.versions.count }.by(1)
      expect(person.versions.last.object_changes).to include("upload_medical_pdf")
    end
  end

  describe "a subject that is not valid" do
    before { person.update_columns(language: "xx") }

    it "stops the change with invalid_subject: :raise" do
      expect { put_file(write(invalid_subject: :raise), "medical").commit! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(WsjrdpDocument.of_subject(person)).to be_empty
      expect(files).to be_empty
    end

    it "is saved anyway by default, with a warning" do
      change = write
      document = put_file(change, "medical").commit!.first.document

      expect(person.reload.upload_medical_pdf).to eq(document.absolute_storage_file_path)
      expect(change.warnings).to contain_exactly(a_string_including("nicht gültig"))
    end
  end

  describe "the lock" do
    # Records, for each call of the file system, whether it ran under the
    # locks of the change (inside Wsjrdp::LockedChange.run's block).
    let(:calls) { [] }

    before do
      inside = false
      allow(Wsjrdp::LockedChange).to receive(:run).and_wrap_original do |original, **options, &block|
        original.call(**options) do |change|
          inside = true
          block.call(change)
        ensure
          inside = false
        end
      end
      allow(File).to receive(:rename).and_wrap_original { |m, *args| calls << [:rename, inside] && m.call(*args) }
      allow(FileUtils).to receive(:rm_f).and_wrap_original { |m, *args| calls << [:rm_f, inside] && m.call(*args) }
    end

    it "holds no file system work: the file is in place before and cleaned up after" do
      put_file(write, "medical", pdf("one")).commit!
      put_file(write, "medical", pdf("one"), now: now + 1).commit!

      expect(calls.map(&:first)).to include(:rename, :rm_f)
      expect(calls.select(&:last)).to be_empty
    end

    it "removes the files of a change that fails under the lock, after it" do
      change = put_file(put_file(write, "medical"), "sepa").on_subject { raise "boom" }

      expect { change.commit! }.to raise_error("boom")
      expect(files).to be_empty
      expect(calls.count { |name, _| name == :rm_f }).to be >= 2
      expect(calls.select(&:last)).to be_empty
    end
  end

  describe "the subject's row" do
    it "is locked first for a kind with a people column" do
      sqls = statements { put_file(write, "medical").commit! }

      lock = sqls.index { |sql| sql.include?("FOR NO KEY UPDATE") }
      expect(lock).to be < sqls.index { |sql| sql.include?("pg_advisory_xact_lock(") }
    end

    it "is locked for every put, also for a kind without a people column, and not saved then" do
      sqls = statements { put_file(write, "letter").commit! }

      lock = sqls.index { |sql| sql.include?("FOR NO KEY UPDATE") }
      expect(lock).to be < sqls.index { |sql| sql.include?("pg_advisory_xact_lock(") }
      expect(sqls.grep(/UPDATE "people"/)).to be_empty
    end

    it "is gone for a subject being destroyed: the put is refused and leaves no file" do
      gone = Fabricate(:person)
      stale = Person.find(gone.id)
      gone.destroy!
      change = described_class.new(subject: stale, by: people(:cmt_leader), origin: "ui")

      expect { put_file(change, "letter").commit! }.to raise_error(ActiveRecord::RecordNotFound)
      gone_folder = root.join("person/pdf/#{stale.id}")
      expect(gone_folder.exist? ? gone_folder.children : []).to be_empty
    end

    it "is not locked to hide a derivation" do
      original = put_file(write, "medical").commit!.first.document
      derivation = Wsjrdp2027::DocumentStore.store!(StringIO.new(pdf("thumb")),
        {derived_from: original, derivation_key: "thumb", filename: "thumb.pdf"}, now: now + 1)

      sqls = statements { write.hide(derivation).commit! }

      expect(sqls.grep(/FOR NO KEY UPDATE/)).to be_empty
      expect(derivation.reload.status).to eq("deleted")
      expect(person.reload.upload_medical_pdf).to eq(original.absolute_storage_file_path)
    end
  end

  it "hides one document, current or not" do
    old = put_file(write, "medical", pdf("old")).commit!.first.document
    new = put_file(write, "medical", pdf("new"), now: now + 1).commit!.first.document

    write.hide(old, reason: "test").commit!

    expect(old.reload.status).to eq("deleted")
    expect(new.reload.status).to eq("current")
    expect(person.reload.upload_medical_pdf).to eq(new.absolute_storage_file_path)
  end

  it "hides a document whose subject is gone, without locking a row" do
    document = put_file(write, "medical").commit!.first.document
    document.update_columns(subject_id: 0)

    sqls = statements { Wsjrdp2027::DocumentStore.hide!(document.reload, reason: "gone") }

    expect(sqls.grep(/FOR NO KEY UPDATE/)).to be_empty
    expect(document.reload).to have_attributes(status: "deleted", subject: nil)
    expect(document.additional_info).to include("deleted_reason" => "gone")
  end

  it "needs the subject's record for everything but a hide" do
    document = put_file(write, "medical").commit!.first.document
    document.update_columns(subject_id: 0)

    expect { described_class.new.hide(document.reload).remove(key: "medical").commit! }
      .to raise_error(ArgumentError, /record/)
  end

  it "refuses documents of another subject" do
    other = Wsjrdp2027::DocumentStore.store!(StringIO.new(pdf), {subject: people(:yp_a_2), key: "letter",
                                                                 filename: "a.pdf"})

    expect { write.hide(other).commit! }.to raise_error(ArgumentError)
  end
end
