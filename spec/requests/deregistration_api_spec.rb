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

  before do
    groups(:unit_a).update_columns(additional_info: {"unit_code" => "#8B0000", "support_cmt_mail_addresses" => unit_bcc})
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-123")
  end

  def headers(accept = "application/json") = {"Accept" => accept, "X-Token" => token.plain_token}

  def json = JSON.parse(response.body)

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
    json
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
      expect(json["contract_names"]).to start_with(person.full_name)
      expect(json["form"]).to include("created_date" => nil)
      expect(json["form"]["file_name"]).to end_with(".pdf")
      expect(json["mail"]).to include(
        "from" => "unit-management@worldscoutjamboree.de",
        "to" => [person.email],
        "bcc" => unit_bcc + ["unit-management@worldscoutjamboree.de"],
        "unit" => {"group_id" => groups(:unit_a).id, "name" => "Unit A", "source" => "unit"}
      )
      expect(json["mail"]["cc"]).to be_an(Array)
      expect(json["birthday"]).to eq(person.birthday&.iso8601)
      expect(json).to include("deregistration_requested_date" => nil, "deregistration_effective_date" => "2026-12-31")
      expect(json["form"]).to include("show_contractual_compensation" => true)
      expect(json["form"].keys).to include("refund_iban", "refund_account_holder")
      expect(json["amounts"].keys).to eq(%w[base_currency regular_full_fee total_fee_reduction total_fee
        amount_paid deregistration_contractual_compensation deregistration_actual_compensation
        deregistration_refund deregistration_open])
      expect(json["amounts"]).to include("base_currency" => "EUR", "deregistration_actual_compensation" => nil)
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
      expect(json["form"]["created_date"]).to eq(state["form"]["created_date"])

      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"
      expect(response).to have_http_status(200)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body.b).to start_with("%PDF")
    end

    it "answers 422 with the reason where there is no form" do
      person.update!(deregistration_kind: "cancellation")

      api_post "/people/#{person.id}/deregistration/create_form.json"

      expect(response).to have_http_status(422)
      expect(json["error"]).to include("Storno")
      expect(person.reload.deregistration_form_created_date).to be_nil
    end

    it "answers 422 for the PDF of a form not made yet" do
      api_get "/people/#{person.id}/deregistration/form.pdf", accept: "application/pdf"

      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("Das Abmelde-Formular ist noch nicht erzeugt.")
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
      expect(json["form_mailings"]).to eq([mailing])
      expect(json["duplicate"]).to be(false)
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

    it "keeps the mails when the form is discarded" do
      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      person.reload.deregistration_form_created_date = nil
      person.save!

      expect(person.reload.deregistration_form_mailings.size).to eq(1)
    end

    it "answers 422 for a form not made yet and for a report that misses a value" do
      state = JSON.parse(Wsjrdp2027::DeregistrationState.new(person).to_json)

      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state)
      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("Das Abmelde-Formular ist noch nicht erzeugt.")

      state = make_form
      api_post "/people/#{person.id}/deregistration/form_sent.json", sent_body(state).except("email_to")
      expect(response).to have_http_status(422)
      expect(json["error"]).to eq("email_to is missing")
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
