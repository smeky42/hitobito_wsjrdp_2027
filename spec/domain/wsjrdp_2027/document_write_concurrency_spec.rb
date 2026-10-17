# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Two writes at once, each in a thread with a connection of its own: the
# locks of Wsjrdp::LockedChange only show between transactions that really
# commit. So these examples run without the transaction around them and
# undo what they write themselves (after).
describe Wsjrdp2027::DocumentWrite do
  self.use_transactional_tests = false

  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:columns) { %w[upload_medical_pdf upload_sepa_pdf status nickname] }
  let!(:saved) { person.attributes.slice(*columns) }
  let!(:inside) { Queue.new }
  let!(:release) { Queue.new }
  # People made for an example, destroyed by it or after it.
  let(:victims) { [] }

  before do
    # These examples commit. Only a test database (hitobito_test_wsjrdp_2027
    # in the dev container, hitobito_test in CI) -- never the development one
    # the dev container's RAILS_DB_NAME names when RAILS_TEST_DB_NAME is unset.
    database = ActiveRecord::Base.connection.current_database
    raise "runs against a test database only, not #{database}" unless Rails.env.test? && database.include?("test")

    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    person.update_columns(upload_medical_pdf: nil, upload_sepa_pdf: nil)
  end

  after do
    WsjrdpDocument.where(subject_type: "Person", subject_id: person.id).delete_all
    PaperTrail::Version.where(item_type: "Person", item_id: person.id).where("created_at > ?", 1.hour.ago).delete_all
    Person.where(id: person.id).update_all(saved)
    victims.each do |id|
      WsjrdpDocument.where(subject_type: "Person", subject_id: id).delete_all
      PaperTrail::Version.where(item_type: "Person", item_id: id).delete_all
      Person.find_by(id: id)&.destroy!
    end
    FileUtils.rm_rf(root)
  end

  def pdf(text) = "%PDF-1.4\n#{text}\n%%EOF\n"

  # Holds the change under its locks until release gets a value.
  def hold(*)
    inside << true
    release.pop
  end

  # Waits until a change holds its locks; a change that died before fails
  # the example instead of making it wait forever.
  def wait_inside = inside.pop(timeout: 10) || raise("no change got inside")

  # A thread with a connection of its own; its value is the block's.
  def in_thread(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { block.call } }.tap do |thread|
      thread.report_on_exception = false
    end
  end

  def put_file(key, text, of: person, timeout: Wsjrdp::LockedChange::DEFAULT_TIMEOUT, &on_subject)
    subject = Person.find(of.id)
    write = Wsjrdp2027::DocumentWrite.new(subject: subject, origin: "ui", timeout: timeout)
    write.put(StringIO.new(pdf(text)), {key: key, filename: "#{key}.pdf"}, now: Time.zone.now)
    write.on_subject(&on_subject) if on_subject
    write.commit!
  end

  # Waits until the thread waits for a lock (or ends).
  def wait_until_blocked(thread)
    50.times do
      break unless thread.alive?
      break if thread.status == "sleep" && waiting_for_lock?

      sleep 0.02
    end
  end

  def waiting_for_lock?
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    ).to_i.positive?
  end

  it "lets the second write of a slot wait and follow the first" do
    first = in_thread { put_file("medical", "first", &method(:hold)) }
    wait_inside
    second = in_thread { put_file("medical", "second") }
    wait_until_blocked(second)

    expect(second).to be_alive
    release << true
    a = first.value.first.document
    b = second.value.first.document

    expect(a.reload.status).to eq("superseded")
    expect(b.reload).to have_attributes(status: "current", replaces_id: a.id)
    expect(person.reload.upload_medical_pdf).to eq(b.absolute_storage_file_path)
  end

  it "lets a write of another slot see what the first wrote" do
    seen = nil
    first = in_thread { put_file("medical", "medical", &method(:hold)) }
    wait_inside
    second = in_thread do
      put_file("sepa", "sepa") { |subject, _| seen = [subject.upload_medical_pdf.present?, subject.upload_sepa_pdf.present?] }
    end
    wait_until_blocked(second)
    release << true
    [first, second].each(&:join)

    expect(seen).to eq([true, true])
    expect(person.reload).to have_attributes(upload_medical_pdf: be_present, upload_sepa_pdf: be_present)
  end

  it "gives up after the timeout and leaves nothing behind" do
    first = in_thread { put_file("medical", "first", &method(:hold)) }
    wait_inside
    second = in_thread { put_file("medical", "second", timeout: 0.3.seconds) }

    expect { second.value }.to raise_error(Wsjrdp::LockedChange::Busy)
    release << true
    first.join
    expect(WsjrdpDocument.of_subject(person).count).to eq(1)
    expect(root.join("person/pdf/#{person.id}").children.size).to eq(1)
  end

  it "makes a destroy of the person wait for a write, then soft-deletes what it wrote" do
    victim = Fabricate(:person)
    victims << victim.id
    first = in_thread { put_file("letter", "a", of: victim, &method(:hold)) }
    wait_inside
    destroying = in_thread { Person.find(victim.id).destroy! }
    wait_until_blocked(destroying)

    expect(destroying).to be_alive
    release << true
    document = first.value.first.document
    destroying.join

    expect(Person.find_by(id: victim.id)).to be_nil
    expect(document.reload).to have_attributes(status: "deleted")
    expect(document.additional_info).to include("deleted_reason" => "subject_destroyed")
  end

  it "refuses a write for a person being destroyed, once the destroy holds the row" do
    victim = Fabricate(:person)
    victims << victim.id
    allow_any_instance_of(Person).to receive(:soft_delete_wsjrdp_documents).and_wrap_original do |original, *args|
      original.call(*args)
      hold
    end
    destroying = in_thread { Person.find(victim.id).destroy! }
    wait_inside
    writing = in_thread { put_file("letter", "a", of: victim) }
    wait_until_blocked(writing)

    expect(writing).to be_alive
    release << true
    destroying.join
    expect { writing.value }.to raise_error(ActiveRecord::RecordNotFound)
    expect(WsjrdpDocument.where(subject_type: "Person", subject_id: victim.id)).to be_empty
    folder = root.join("person/pdf/#{victim.id}")
    expect(folder.exist? ? folder.children : []).to be_empty
  end

  describe Wsjrdp::LockedChange do
    it "does not hold up a change with other keys" do
      first = in_thread { described_class.run(keys: ["a"], &method(:hold)) }
      wait_inside

      second = in_thread { described_class.run(keys: ["b"], timeout: 1.second) { :done } }

      expect(second.value).to eq(:done)
      release << true
      first.join
    end

    it "takes crossed keys without a deadlock" do
      threads = 2.times.map do |i|
        keys = i.zero? ? %w[k1 k2 k3] : %w[k3 k2 k1]
        in_thread { 20.times { described_class.run(keys: keys) { sleep 0.002 } } }
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe Wsjrdp2027::RegistrationDocuments::Import do
    # The examples' upload root lies outside /private/uploads/, by which the
    # scan reads the paths of the people columns.
    before { stub_const("Wsjrdp2027::RegistrationDocuments::UPLOADS_MARKER", "#{root}/") }

    def chain = Wsjrdp2027::RegistrationDocuments::Scan.new(person_ids: [person.id]).run.chain(person.id, "medical")

    it "fails a chain whose slot a write holds past the timeout, and skips it once the write changed it" do
      first = put_file("medical", "a").first.document
      scanned = chain
      expect(scanned.state).to eq(:complete)
      second = in_thread { put_file("medical", "b", &method(:hold)) }
      wait_inside

      stub_const("Wsjrdp::LockedChange::DEFAULT_TIMEOUT", 0.3.seconds)
      busy = described_class.new.register([scanned])
      release << true
      second.join
      stale = described_class.new.register([scanned])

      expect(busy.to_h).to include(chains: 0, failed: 1)
      expect(busy.errors.first).to start_with(scanned.id)
      expect(stale.to_h).to include(chains: 0, failed: 0, skipped: 1)
      expect(WsjrdpDocument.current_for(person, key: "medical").replaces_id).to eq(first.id)
    end

    it "stamps the checked files without waiting for a row someone writes" do
      held = put_file("medical", "a").first.document
      free = put_file("sepa", "b").first.document
      holder = in_thread { Wsjrdp::LockedChange.run(rows: [held], &method(:hold)) }
      wait_inside
      entries = [held, free].map { |document| Wsjrdp2027::RegistrationDocuments::Entry.new(document: document) }
      chain = Wsjrdp2027::RegistrationDocuments::Chain.new(entries: entries)
      later = 1.hour.from_now.change(usec: 0)

      begin
        stamping = in_thread { Wsjrdp2027::RegistrationDocuments::Import.new(now: later).checked([chain]) }
        finished = stamping.join(5)
      ensure
        release << true
        holder.join
      end

      expect(finished).not_to be_nil
      expect(free.reload.file_checked_at).to eq(later)
      expect(held.reload.file_checked_at).not_to eq(later)
    end
  end
end
