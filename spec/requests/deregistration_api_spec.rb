# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The scripts' API of the Abmeldung page (Person::DeregistrationController):
# an API key with people and people:log and an acting person reads the
# deregistration, makes the Abmelde-Formular, fetches its PDF and reports the
# mail it sent it with -- the note, the log entry and the element of
# form_mailings that report leaves.
describe "Deregistration API", type: :request do
  let(:person) { people(:yp_a_1) }
  let(:acting_person) { people(:admin) }
  let(:scopes) { %w[people people:log] }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "deregistration", permission: "layer_and_below_full",
      acting_person: acting_person, scopes: scopes)
  end
  let(:unit_bcc) { %w[unit-manager@worldscoutjamboree.de] }
  # An upload root of its own, so the kept forms and mails land nowhere else.
  let(:upload_root) { Pathname(Dir.mktmpdir("wsjrdp-deregistration-api")) }

  after { FileUtils.rm_rf(upload_root) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(upload_root)
    groups(:unit_a).update_columns(additional_info: {"unit_code" => "#8B0000", "support_cmt_mail_addresses" => unit_bcc})
    # Everything a complete form needs; examples take a piece away.
    person.update_columns(birthday: Date.new(2010, 6, 1), additional_contact_name_a: "Erika UnitA",
      additional_contact_single: true)
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-123",
      deregistration_actual_compensation_cents: 15_000)
  end

  def headers(accept = "application/json") = {"Accept" => accept, "X-Token" => token.plain_token}

  def json = JSON.parse(response.body)

  # The deregistration a POST answers with, nested.
  def answered = json["deregistration"]

  def error_codes = json["errors"].pluck("code")

  def error_text = json["errors"].pluck("message").join(" ")

  def api_get(path, accept: "application/json") = get(path, headers: headers(accept))

  def api_post(path, body = {})
    post path, params: body.to_json, headers: headers.merge("Content-Type" => "application/json")
  end

  def sent_body(state, message_id: "<1@worldscoutjamboree.de>")
    {
      "email_sent_at" => "2026-11-15T14:03:12+01:00",
      "email_to" => ["yp1.unita@wsjrdp.example.com"],
      "email_cc" => ["parent@example.org"],
      "email_bcc" => state["mail"]["bcc"],
      "email_subject" => "WSJ27 Abmeldung #{state["role_id_name"]} HELP-123",
      "email_message_id" => message_id,
      "script" => "registration_tools/create_deregistration_form.py",
      "deregistration" => state
    }
  end

  def make_form
    api_post "/people/#{person.id}/deregistration/create_form.json"
    answered
  end

  describe "GET deregistration.json" do
    it "answers what the form and its mail need" do
      api_get "/people/#{person.id}/deregistration.json"

      expect(response).to have_http_status(200)
      expect(json).to include(
        "person_id" => person.id, "kind" => "withdrawal", "available" => true,
        "not_available_reason" => nil, "issue" => "HELP-123",
        "status" => person.status, "contract_status" => person.contract_status,
        "role_id_name" => "YP #{person.id} #{person.short_full_name}",
        "form_mailings" => []
      )
      expect(json["contract_names"]).to eq([person.full_name, "Erika UnitA"])
      expect(json["form"]).to include("created_date" => nil)
      expect(json["form"]["file_name"]).to end_with(".pdf")
      expect(json["mail"]).to include(
        "from" => "unit-management@worldscoutjamboree.de",
        "reply_to" => [],
        "to" => [person.email],
        "bcc" => unit_bcc + ["unit-management@worldscoutjamboree.de"],
        "unit" => {"group_id" => groups(:unit_a).id, "name" => "Unit A", "source" => "unit"}
      )
      expect(json["mail"]["cc"]).to be_an(Array)
      expect(json["mail"]).to include("subject" => "WSJ27 Abmeldung YP #{person.id} #{person.short_full_name} HELP-123",
        "confirmation_subject" => "WSJ27 Bestätigung der Abmeldung YP #{person.id} #{person.short_full_name} HELP-123")
      expect(json["birthday"]).to eq(person.birthday&.iso8601)
      expect(json).to include("deregistration_requested_date" => nil, "deregistration_effective_date" => "2026-12-31")
      expect(json["form"]).to include("show_contractual_compensation" => true)
      expect(json["form"].keys).to include("refund_iban", "refund_account_holder")
      expect(json["amounts"].keys).to eq(%w[base_currency regular_full_fee total_fee_reduction total_fee
        amount_paid deregistration_contractual_compensation deregistration_actual_compensation
        deregistration_refund deregistration_open])
      expect(json["amounts"]).to include("base_currency" => "EUR", "deregistration_actual_compensation" => 150)
      expect(json["form_check"]).to eq("errors" => [], "warnings" => [])
    end

    it "answers the amounts in euros, whole ones as integers" do
      person.update!(deregistration_actual_compensation_cents: 40295)
      AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: 144000,
        amount_currency: "EUR", description: "Teilnahmebeitrag",
        value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))

      api_get "/people/#{person.id}/deregistration.json"

      amounts = json["amounts"]
      expect(amounts["deregistration_actual_compensation"]).to eq(402.95)
      expect(amounts["amount_paid"]).to eq(1440)
      expect(amounts["amount_paid"]).to be_an(Integer)
      expect(amounts["deregistration_refund"]).to eq(1037.05)
      expect(amounts["deregistration_open"]).to eq(0)
    end

    it "answers the refund account the made form captured, not the one changed since" do
      person.update!(sepa_iban: "DE02120300000000202051", sepa_name: "Kim Muster",
        deregistration_form_show_contractual_compensation: false)
      make_form
      person.reload.update!(sepa_iban: "DE88100900001234567892", sepa_name: "Anders")

      api_get "/people/#{person.id}/deregistration.json"

      expect(json["form"]).to include("refund_iban" => "DE02120300000000202051",
        "refund_account_holder" => "Kim Muster", "show_contractual_compensation" => false)
    end

    it "says why there is no form" do
      person.update!(deregistration_kind: "termination")

      api_get "/people/#{person.id}/deregistration.json"

      expect(json["available"]).to be(false)
      expect(json["not_available_reason"]).to include("Kündigung")
    end

    context "without people:log" do
      let(:scopes) { %w[people] }

      it "is refused" do
        api_get "/people/#{person.id}/deregistration.json"

        expect(response).to have_http_status(403)
      end
    end
  end

  describe "POST create_form.json and GET form.pdf" do
    it "makes the form once and answers its PDF" do
      state = make_form

      expect(response).to have_http_status(200)
      expect(state["form"]["created_date"]).to eq(Date.current.iso8601)
      expect(state["form"]["reply_due_date"]).to eq((Date.current + 14.days).iso8601)

      travel_to(Date.current + 3.days) { make_form }
      expect(answered["form"]["created_date"]).to eq(state["form"]["created_date"])

      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"
      expect(response).to have_http_status(200)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body.b).to start_with("%PDF")
    end

    it "answers 422 with the reason where there is no form" do
      person.update!(deregistration_kind: "cancellation")

      api_post "/people/#{person.id}/deregistration/create_form.json"

      expect(response).to have_http_status(422)
      expect(error_codes).to eq(["unavailable_cancellation"])
      expect(error_text).to include("Storno")
      expect(person.reload.deregistration_form_created_date).to be_nil
    end

    it "answers 409 for the PDF of a form not made yet" do
      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"

      expect(response).to have_http_status(409)
      expect(json["errors"]).to eq([{"code" => "form_not_created", "message" => "Das Abmelde-Formular ist noch nicht erzeugt."}])
    end
  end

  describe "POST prepare_form.json" do
    def prepare = api_post("/people/#{person.id}/deregistration/prepare_form.json")

    it "notes the deregistration on the person, makes the form and answers the deregistration" do
      person.update_columns(status: "confirmed")

      with_versioning { prepare }

      expect(response).to have_http_status(200)
      expect(json).to include("errors" => [], "warnings" => [])
      expect(answered).to include("status" => "deregistration_noted", "deregistration_status" => "form_created")
      expect(answered["form"]["created_date"]).to eq(Date.current.iso8601)
      version = PaperTrail::Version.where(item: person, event: "update").last
      expect(version.changeset["status"]).to eq(%w[confirmed deregistration_noted])
      expect(version).to have_attributes(whodunnit: token.id.to_s, whodunnit_type: "ServiceToken")
    end

    it "leaves a status that is under way, and a form made already" do
      person.update_columns(status: "deregistered")
      prepare
      created = answered["form"]["created_date"]

      travel_to(Date.current + 2.days) { prepare }

      expect(answered).to include("status" => "deregistered")
      expect(answered["form"]["created_date"]).to eq(created)
    end

    it "keeps the PDF and its picture before it answers, and form.pdf hands that PDF to the script" do
      prepare

      document = person.reload.deregistration.sent_form_document
      expect(answered["form"]["document_id"]).to eq(document.id)
      expect(document).to have_attributes(key: "deregistration", secondary_key: "form", origin: "api")
      expect(document.derivatives.pluck(:derivation_key)).to eq(["thumbnail"])

      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"
      expect(response.body.b).to eq(File.binread(Wsjrdp2027::DocumentStore.path_for(document)))
    end

    it "takes the kept form on the next prepare and keeps no new one" do
      prepare
      first = answered["form"]["document_id"]

      expect { prepare }.not_to change(WsjrdpDocument, :count)
      expect(answered["form"]["document_id"]).to eq(first)

      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(answered)
      expect { prepare }.not_to change(WsjrdpDocument, :count)
      expect(answered["form"]["document_id"]).to eq(first)
    end

    it "keeps a new version where the kept one no longer says what the data say" do
      person.update!(sepa_iban: "DE02120300000000202051", sepa_name: "Kim Muster")
      prepare
      first = answered["form"]["document_id"]
      AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: 20_000, amount_currency: "EUR",
        description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))

      prepare

      expect(json["errors"]).to eq([])
      second = answered["form"]["document_id"]
      expect(second).not_to eq(first)
      expect(WsjrdpDocument.find(first).status).to eq("superseded")
      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"
      expect(response.body.b).to eq(File.binread(Wsjrdp2027::DocumentStore.path_for(WsjrdpDocument.find(second))))
    end

    it "answers 503 busy while the documents are busy" do
      allow(Wsjrdp::LockedChange).to receive(:run).and_raise(Wsjrdp::LockedChange::Busy, "busy")

      prepare

      expect(response).to have_http_status(503)
      expect(error_codes).to eq(["busy"])
    end

    it "keeps the form anew where the kept one is gone" do
      prepare
      first = WsjrdpDocument.find(answered["form"]["document_id"])
      first.update_columns(file_status: WsjrdpDocument::FILE_MISSING)

      prepare

      expect(answered["form"]["document_id"]).not_to eq(first.id)
      expect(first.reload.status).to eq("superseded")
    end

    it "stores the form before the mail: PDF, picture, then the EML" do
      prepare
      eml = "Message-ID: <1@worldscoutjamboree.de>\r\nSubject: x\r\n\r\nHallo\r\n"
      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(answered).merge("email_eml_base64" => Base64.strict_encode64(eml))

      expect(WsjrdpDocument.where(subject: person).order(:id).map { |d| [d.secondary_key, d.derivation_key] })
        .to eq([["form", nil], ["form", "thumbnail"], ["form_mail", nil]])
    end

    it "writes nothing where there is no form" do
      person.update_columns(status: "confirmed")
      person.update!(deregistration_kind: "termination")

      prepare

      expect(response).to have_http_status(422)
      expect(error_codes).to eq(["unavailable_termination"])
      expect(error_text).to include("Kündigung")
      expect(person.reload.status).to eq("confirmed")
      expect(person.deregistration_form_created_date).to be_nil
    end

    # A form with a blank to fill in by hand does not go out: every gap at
    # once, the warnings beside them, and nothing written.
    it "refuses an incomplete form with every error and warning" do
      person.update_columns(status: "confirmed", birthday: nil)
      person.update!(deregistration_actual_compensation_cents: nil, deregistration_issue: nil)

      prepare

      expect(response).to have_http_status(422)
      expect(error_codes).to eq(%w[no_compensation no_birthday])
      expect(json["warnings"].pluck("code")).to eq(["no_issue"])
      expect(answered["form_check"]["errors"].pluck("code")).to eq(%w[no_compensation no_birthday])
      expect(person.reload.status).to eq("confirmed")
      expect(person.deregistration_form_created_date).to be_nil
    end

    it "wants the account where the form names a refund" do
      AccountingEntry.create!(subject: person, author: people(:admin), amount_cents: 20_000, amount_currency: "EUR",
        description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
      person.update_columns(sepa_iban: nil)

      prepare

      expect(response).to have_http_status(422)
      expect(error_codes).to eq(["no_refund_account"])
    end

    it "lets a warning through, and answers it" do
      person.update!(deregistration_issue: nil)

      prepare

      expect(response).to have_http_status(200)
      expect(json["warnings"].pluck("code")).to eq(["no_issue"])
    end
  end

  describe "GET form.pdf once the form went out" do
    it "answers the PDF that was sent, as stored" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      document = person.reload.deregistration.sent_form_document
      stored = File.binread(Wsjrdp2027::DocumentStore.path_for(document))

      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"

      expect(response).to have_http_status(200)
      expect(response.body.b).to eq(stored)
    end

    it "keeps the first page as a picture beside it, and answers that picture" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      document = person.reload.deregistration.sent_form_document
      thumbnail = document.derivatives.sole

      expect(thumbnail).to have_attributes(derivation_key: "thumbnail", subject: person, key: "deregistration",
        key_number: document.key_number, secondary_key: "form", content_type: "image/png", origin: "api",
        filename: state["form"]["file_name"].sub(/\.pdf\z/, ".png"))
      stored = File.binread(Wsjrdp2027::DocumentStore.path_for(thumbnail))

      api_get "/people/#{person.id}/deregistration/form.png", accept: "image/png"

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq("image/png")
      expect(response.body.b).to eq(stored)
    end
  end

  describe "POST form_sent.json" do
    it "records the mail as a note, a log entry and an element of form_mailings" do
      state = make_form

      expect { api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state) }
        .to change { Note.count }.by(1).and change { PaperTrail::Version.where(event: "wsjrdp_note").count }.by(1)
      expect(response).to have_http_status(201)

      note = Note.last
      expect(note.subject).to eq(person)
      expect(note.author).to eq(acting_person)
      expect(note.text).to eq("Abmelde-Formular am 15.11.2026 per E-Mail verschickt (HELP-123)")

      version = PaperTrail::Version.where(event: "wsjrdp_note").last
      expect(version.item).to eq(person)
      expect(version.whodunnit).to eq(token.id.to_s)
      expect(version.whodunnit_type).to eq("ServiceToken")
      expect(version.additional_info).to eq("script" => "registration_tools/create_deregistration_form.py")
      expect(version.wsjrdp_data).to include(
        "category" => "deregistration_form",
        "message" => "an yp1.unita@wsjrdp.example.com, parent@example.org · HELP-123",
        "email_bcc" => state["mail"]["bcc"],
        "email_message_id" => "<1@worldscoutjamboree.de>",
        "deregistration_issue" => "HELP-123",
        "form_created_date" => state["form"]["created_date"],
        "note_id" => note.id,
        "deregistration" => state
      )

      mailing = person.reload.deregistration_form_mailings.sole
      expect(mailing).to include("log_version_id" => version.id, "note_id" => note.id,
        "form_created_date" => state["form"]["created_date"], "email_subject" => sent_body(state)["email_subject"])
      expect(json["form_mailing"]).to eq(mailing)
      expect(answered["form_mailings"]).to eq([mailing])
      expect(json["duplicate"]).to be(false)
    end

    it "refuses a report while there is no kept form, and keeps none" do
      state = make_form
      person.reload.deregistration.update_columns(sent_form_document_id: nil)

      expect { api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state) }
        .not_to change(WsjrdpDocument, :count)

      expect(response).to have_http_status(409)
      expect(error_codes).to eq(["form_document_missing"])
      expect(person.reload.deregistration).to have_attributes(form_sent_at: nil, sent_form_document_id: nil)
      expect(person.deregistration_form_mailings).to be_empty
    end

    it "answers a mail recorded already as such, even once its form is gone" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      person.reload.deregistration.sent_form_document.update_columns(file_status: WsjrdpDocument::FILE_MISSING)

      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)

      expect(response).to have_http_status(200)
      expect(json["duplicate"]).to be(true)
    end

    it "replaces an EML a failed report left behind, so the report can be sent again" do
      state = make_form
      body = sent_body(state).merge("email_eml_base64" => Base64.strict_encode64(eml("<1@worldscoutjamboree.de>")))
      allow(Wsjrdp::LogEntry).to receive(:note!).and_raise(ActiveRecord::RecordInvalid)
      begin
        api_post "/people/#{person.id}/deregistration/form_sent.json", body
      rescue ActiveRecord::RecordInvalid
        nil # raised or answered as an error page, depending on show_exceptions
      end
      expect(person.reload.deregistration_form_mailings).to be_empty
      allow(Wsjrdp::LogEntry).to receive(:note!).and_call_original

      api_post "/people/#{person.id}/deregistration/form_sent.json", body

      expect(response).to have_http_status(201)
      mails = WsjrdpDocument.where(subject: person, secondary_key: "form_mail").order(:id)
      expect(mails.map { |d| [d.secondary_key_number, d.status] }).to eq([[1, "superseded"], [1, "current"]])
      expect(person.reload.deregistration_form_mailings.sole["eml_document_id"]).to eq(mails.last.id)
    end

    it "refuses a report whose form document is not the deregistration's" do
      state = make_form
      state["form"]["document_id"] = state["form"]["document_id"] + 1000

      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)

      expect(response).to have_http_status(409)
      expect(error_codes).to eq(["other_form_document"])
    end

    it "writes no person version of its own" do
      state = make_form

      expect { api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state) }
        .not_to change { PaperTrail::Version.where(item: person, event: "update").count }
    end

    it "records a Message-ID once" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)

      expect { api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state) }
        .not_to change { Note.count }
      expect(response).to have_http_status(200)
      expect(json["duplicate"]).to be(true)
      expect(person.reload.deregistration_form_mailings.size).to eq(1)
    end

    it "fixes the form with the first mail: status, time, the sent form as a document" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)

      row = person.reload.deregistration
      expect(row).to have_attributes(status: "form_sent", form_sent_at: Time.zone.iso8601("2026-11-15T14:03:12+01:00"))
      expect(row.sent_form_document).to have_attributes(subject: person, key: "deregistration",
        key_number: row.number, secondary_key: "form", key_ref: row, filename: state["form"]["file_name"],
        origin: "api", origin_service_token: token)
      expect(row.events.map { |e| [e.event, e.action] }).to include(["notify", "form_sent"])

      person.deregistration_form_created_date = nil
      expect(person.save).to be(false)
      expect(person.reload.deregistration_form_mailings.size).to eq(1)
    end

    it "keeps the first sent form when the form goes out again" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      first = person.reload.deregistration.sent_form_document_id
      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(answered, message_id: "<2@worldscoutjamboree.de>")

      expect(response).to have_http_status(201)
      expect(person.reload.deregistration.sent_form_document_id).to eq(first)
      expect(person.deregistration_form_mailings.size).to eq(2)
    end

    def eml(message_id) = "Message-ID: #{message_id}\r\nSubject: WSJ27 Abmeldung\r\n\r\nHallo\r\n"

    it "keeps the mail as an EML, numbered per mail, and names it in the event and the log entry" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(state).merge("email_eml_base64" => Base64.strict_encode64(eml("<1@worldscoutjamboree.de>")))
      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(answered, message_id: "<2@worldscoutjamboree.de>")
          .merge("email_eml_base64" => Base64.strict_encode64(eml("<2@worldscoutjamboree.de>")))

      expect(response).to have_http_status(201)
      row = person.reload.deregistration
      mails = WsjrdpDocument.where(subject: person, secondary_key: "form_mail").order(:secondary_key_number)
      expect(mails.map { |d| [d.key, d.key_number, d.secondary_key_number, d.content_type, d.origin] })
        .to eq([["deregistration", row.number, 1, "message/rfc822", "api"], ["deregistration", row.number, 2, "message/rfc822", "api"]])
      expect(mails.first.key_ref).to eq(row)
      expect(File.binread(Wsjrdp2027::DocumentStore.path_for(mails.last))).to eq(eml("<2@worldscoutjamboree.de>"))
      expect(row.form_mailings.pluck("eml_document_id")).to eq(mails.map(&:id))
      expect(PaperTrail::Version.where(event: "wsjrdp_note").last.wsjrdp_data["eml_document_id"]).to eq(mails.last.id)
    end

    it "refuses an EML of another mail" do
      state = make_form

      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(state).merge("email_eml_base64" => Base64.strict_encode64(eml("<other@example.org>")))

      expect(response).to have_http_status(422)
      expect(error_text).to include("is not email_message_id")
      expect(WsjrdpDocument.where(subject: person, secondary_key: "form_mail")).to be_empty
    end

    it "refuses a report for another version of the deregistration" do
      state = make_form

      api_post "/people/#{person.id}/deregistration/form_sent.json",
        sent_body(state.merge("deregistration_id" => state["deregistration_id"] + 1))

      expect(response).to have_http_status(409)
      expect(error_codes).to eq(["other_deregistration"])
      expect(error_text).to include("the current one is #{state["deregistration_id"]}")
    end

    it "answers 422 for a form not made yet and for a report that misses a value" do
      state = JSON.parse(Wsjrdp2027::DeregistrationState.new(person).to_json)

      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      expect(response).to have_http_status(409)
      expect(error_codes).to eq(["form_not_created"])

      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state).except("email_to")
      expect(response).to have_http_status(422)
      expect(json["errors"]).to eq([{"code" => "invalid_report", "message" => "email_to is missing"}])
    end

    it "records a confirmation without a person note, and moves the row on" do
      person.update!(deregistration_kind: "termination")
      api_get "/people/#{person.id}/deregistration.json"
      state = json

      expect do
        api_post "/people/#{person.id}/deregistration/confirmation_sent.json",
          sent_body(state).merge("email_subject" => "WSJ27 Bestätigung der Abmeldung")
      end.not_to change { Note.count }

      expect(response).to have_http_status(201)
      expect(json["confirmation_mailing"]).to include("email_subject" => "WSJ27 Bestätigung der Abmeldung")
      expect(answered["confirmation_mailings"].size).to eq(1)
      expect(answered["form_mailings"]).to eq([])
      expect(person.reload.deregistration.status).to eq("confirmation_sent")
      version = PaperTrail::Version.where(event: "wsjrdp_note").last
      expect(version.wsjrdp_data).to include("category" => "deregistration_confirmation")
    end

    it "is the API key's only" do
      sign_in(people(:admin))

      expect do
        post "/people/#{person.id}/deregistration/form_sent.json", params: "{}",
          headers: {"Content-Type" => "application/json", "Accept" => "application/json"}
      end.not_to change { Note.count }
      expect(response).to have_http_status(403)
    end
  end
end
