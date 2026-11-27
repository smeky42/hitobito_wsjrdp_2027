# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DeregistrationFormSent do
  let(:person) { people(:yp_a_1) }
  let(:acting_person) { people(:admin) }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "deregistration", permission: "layer_and_below_full",
      acting_person: acting_person, scopes: %w[people people:log])
  end
  let(:upload_root) { Pathname(Dir.mktmpdir("wsjrdp-deregistration-sent")) }

  after { FileUtils.rm_rf(upload_root) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(upload_root)
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_pdf).and_return("%PDF-1.4\n%stub\n")
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_png).and_return("\x89PNG\r\n\x1a\nstub".b)
    person.update_columns(birthday: Date.new(2010, 6, 1), additional_contact_name_a: "Erika UnitA",
      additional_contact_single: true)
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-123",
      deregistration_actual_compensation_cents: 15_000)
  end

  def state = JSON.parse(Wsjrdp2027::DeregistrationState.new(person.reload).to_json)

  def make_form
    Wsjrdp2027::DeregistrationForm.new(person.reload).record_creation!
    Wsjrdp2027::DeregistrationFormDocument.new(person.reload, author: acting_person, service_token: token).store!
    state
  end

  def eml(message_id) = "Message-ID: #{message_id}\r\nSubject: WSJ27 Abmeldung\r\n\r\nHallo\r\n"

  def report(deregistration, message_id: "<1@worldscoutjamboree.de>", with_eml: false)
    body = {
      "email_sent_at" => "2026-11-15T14:03:12+01:00",
      "email_to" => ["yp1.unita@wsjrdp.example.com"],
      "email_cc" => ["parent@example.org"],
      "email_bcc" => deregistration["mail"]["bcc"],
      "email_subject" => "WSJ27 Abmeldung #{deregistration["role_id_name"]} HELP-123",
      "email_message_id" => message_id,
      "script" => "registration_tools/create_deregistration_form.py",
      "deregistration" => deregistration
    }
    with_eml ? body.merge("email_eml_base64" => Base64.strict_encode64(eml(message_id))) : body
  end

  def record(payload, klass: described_class) = klass.new(person.reload, payload, service_token: token).save!

  def refusal(payload)
    record(payload)
    nil
  rescue described_class::Invalid => e
    [e.code, e.status]
  end

  def form_mails = WsjrdpDocument.where(subject: person, secondary_key: "form_mail").order(:id)

  it "records the mail as a note, a log entry and an event, and fixes the form with the first one" do
    deregistration = make_form

    sent = nil
    expect { with_versioning { sent = record(report(deregistration)) } }
      .not_to change { PaperTrail::Version.where(item: person, event: "update").count }

    aggregate_failures do
      expect(sent.duplicate?).to be(false)
      note = Note.last
      expect(note).to have_attributes(subject: person, author: acting_person,
        text: "Abmelde-Formular am 15.11.2026 per E-Mail verschickt (HELP-123)")
      version = PaperTrail::Version.where(event: "wsjrdp_note").last
      expect(version).to have_attributes(item: person, whodunnit: token.id.to_s, whodunnit_type: "ServiceToken",
        additional_info: {"script" => "registration_tools/create_deregistration_form.py"})
      expect(version.wsjrdp_data).to include("category" => "deregistration_form",
        "message" => "an yp1.unita@wsjrdp.example.com, parent@example.org · HELP-123",
        "email_bcc" => deregistration["mail"]["bcc"], "email_message_id" => "<1@worldscoutjamboree.de>",
        "deregistration_issue" => "HELP-123", "form_created_date" => deregistration["form"]["created_date"],
        "note_id" => note.id, "deregistration" => deregistration)
      mailing = person.reload.deregistration_form_mailings.sole
      expect(mailing).to eq(sent.mailing)
      expect(mailing).to include("log_version_id" => version.id, "note_id" => note.id,
        "form_created_date" => deregistration["form"]["created_date"])

      row = person.deregistration
      expect(row).to have_attributes(status: "form_sent", form_sent_at: Time.zone.iso8601("2026-11-15T14:03:12+01:00"),
        sent_form_document_id: deregistration["form"]["document_id"])
      expect(row.sent_form_document).to have_attributes(key_ref: row, origin: "api", origin_service_token: token)
      expect(row.events.map { |e| [e.event, e.action] }).to include(["notify", "form_sent"])
      person.deregistration_form_created_date = nil
      expect(person.save).to be(false)
    end
  end

  it "answers a Message-ID recorded already as it was, even once its form is gone" do
    deregistration = make_form
    first = record(report(deregistration))
    person.reload.deregistration.sent_form_document.update_columns(file_status: WsjrdpDocument::FILE_MISSING)

    again = nil
    expect { again = record(report(deregistration)) }.not_to change { Note.count }

    expect(again.duplicate?).to be(true)
    expect(again.mailing).to eq(first.mailing)
    expect(person.reload.deregistration_form_mailings.size).to eq(1)
  end

  it "keeps each mail as an EML numbered per mail, after the PDF and its picture, and keeps the first sent form" do
    make_form
    record(report(state, with_eml: true))
    first_form = person.reload.deregistration.sent_form_document_id
    record(report(state, message_id: "<2@worldscoutjamboree.de>", with_eml: true))

    row = person.reload.deregistration
    aggregate_failures do
      expect(WsjrdpDocument.where(subject: person).order(:id).map { |d| [d.secondary_key, d.derivation_key] })
        .to eq([["form", nil], ["form", "thumbnail"], ["form_mail", nil], ["form_mail", nil]])
      expect(form_mails.map { |d| [d.key_number, d.secondary_key_number, d.content_type, d.key_ref] })
        .to eq([[row.number, 1, "message/rfc822", row], [row.number, 2, "message/rfc822", row]])
      expect(File.binread(Wsjrdp2027::DocumentStore.path_for(form_mails.last))).to eq(eml("<2@worldscoutjamboree.de>"))
      expect(row.form_mailings.pluck("eml_document_id")).to eq(form_mails.map(&:id))
      expect(PaperTrail::Version.where(event: "wsjrdp_note").last.wsjrdp_data["eml_document_id"]).to eq(form_mails.last.id)
      expect(row.sent_form_document_id).to eq(first_form)
    end
  end

  it "replaces an EML a failed report left behind, so the report can be sent again" do
    payload = report(make_form, with_eml: true)
    allow(Wsjrdp::LogEntry).to receive(:note!).and_raise(ActiveRecord::RecordInvalid)
    expect { record(payload) }.to raise_error(ActiveRecord::RecordInvalid)
    allow(Wsjrdp::LogEntry).to receive(:note!).and_call_original

    record(payload)

    expect(form_mails.map { |d| [d.secondary_key_number, d.status] }).to eq([[1, "superseded"], [1, "current"]])
    expect(person.reload.deregistration_form_mailings.sole["eml_document_id"]).to eq(form_mails.last.id)
  end

  # A row migrated from people.additional_info whose form went out before
  # forms were kept has no document; its further mails are recorded.
  it "records a further mail of a form sent before forms were kept" do
    deregistration = make_form
    row = person.reload.deregistration
    row.update_columns(sent_form_document_id: nil, form_sent_at: Time.zone.local(2026, 9, 1), status: "form_sent")
    row.events.create!(event: "create", action: WsjrdpDeregistration::MIGRATED_ACTION, occurred_at: Time.current)
    deregistration["form"]["document_id"] = nil

    expect(record(report(deregistration)).duplicate?).to be(false)
  end

  describe "refuses" do
    it "a form not made yet" do
      expect(refusal(report(state))).to eq(["form_not_created", :conflict])
    end

    it "a report for another version of the deregistration" do
      deregistration = make_form

      expect(refusal(report(deregistration.merge("deregistration_id" => deregistration["deregistration_id"] + 1))))
        .to eq(["other_deregistration", :conflict])
    end

    it "a report that misses a value" do
      expect(refusal(report(make_form).except("email_to"))).to eq(["invalid_report", :unprocessable_entity])
    end

    it "an EML of another mail, and keeps none" do
      payload = report(make_form).merge("email_eml_base64" => Base64.strict_encode64(eml("<other@example.org>")))

      expect(refusal(payload)).to eq(["invalid_report", :unprocessable_entity])
      expect(form_mails).to be_empty
    end

    it "a report while there is no kept form, and keeps none" do
      deregistration = make_form
      person.reload.deregistration.update_columns(sent_form_document_id: nil)

      documents = WsjrdpDocument.count

      expect(refusal(report(deregistration))).to eq(["form_document_missing", :conflict])
      expect(WsjrdpDocument.count).to eq(documents)
      expect(person.reload.deregistration).to have_attributes(form_sent_at: nil, sent_form_document_id: nil)
      expect(person.deregistration_form_mailings).to be_empty
    end

    it "a report whose form document is not the deregistration's" do
      deregistration = make_form

      expect(refusal(report(deregistration.deep_merge("form" => {"document_id" => deregistration["form"]["document_id"] + 1000}))))
        .to eq(["other_form_document", :conflict])
    end

    it "a further mail of a sent form that lost its document, unless the row was migrated" do
      deregistration = make_form
      person.reload.deregistration.update_columns(sent_form_document_id: nil, form_sent_at: Time.zone.local(2026, 9, 1),
        status: "form_sent")
      deregistration["form"]["document_id"] = nil

      expect(refusal(report(deregistration))).to eq(["form_document_missing", :conflict])
    end
  end

  describe ".with_report_lock" do
    it "is busy while another report of the row runs" do
      deregistration = make_form
      stub_const("Wsjrdp2027::DeregistrationFormSent::REPORT_LOCK_TIMEOUT", 0.seconds)

      holding_session_lock(described_class.report_lock_key(person.reload.deregistration)) do
        expect { record(report(deregistration)) }.to raise_error(Wsjrdp::LockedChange::Busy)
      end
      expect(person.reload.deregistration_form_mailings).to be_empty
    end

    it "is released after a report it refused and after one it recorded" do
      deregistration = make_form
      lock_key = described_class.report_lock_key(person.reload.deregistration)

      refusal(report(deregistration.deep_merge("form" => {"document_id" => 0})))
      expect(session_lock_free?(lock_key)).to be(true)

      record(report(deregistration))
      expect(session_lock_free?(lock_key)).to be(true)
    end
  end

  describe Wsjrdp2027::DeregistrationConfirmationSent do
    it "records a confirmation of a termination without a person note, and moves the row on" do
      person.update!(deregistration_kind: "termination")

      expect { record(report(state).merge("email_subject" => "WSJ27 Bestätigung"), klass: described_class) }
        .not_to change { Note.count }

      answered = state
      expect(answered["confirmation_mailings"].sole).to include("email_subject" => "WSJ27 Bestätigung")
      expect(answered["form_mailings"]).to eq([])
      expect(person.deregistration.status).to eq("confirmation_sent")
      expect(PaperTrail::Version.where(event: "wsjrdp_note").last.wsjrdp_data)
        .to include("category" => "deregistration_confirmation")
    end
  end
end
