# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The scripts' API of the Abmeldung page: an API key with people and
# people:log and an acting person reads the deregistration, makes the
# Abmelde-Formular, fetches its PDF and reports the mails it sent.
describe "Deregistration API", type: :request do
  let(:person) { people(:yp_a_1) }
  let(:scopes) { %w[people people:log] }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "deregistration", permission: "layer_and_below_full",
      acting_person: people(:admin), scopes: scopes)
  end
  let(:upload_root) { Pathname(Dir.mktmpdir("wsjrdp-deregistration-api")) }
  let(:pdf) { "%PDF-1.4\n%stub\n" }
  let(:png) { "\x89PNG\r\n\x1a\nstub".b }

  after { FileUtils.rm_rf(upload_root) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(upload_root)
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_pdf).and_return(pdf)
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_png).and_return(png)
    person.update_columns(birthday: Date.new(2010, 6, 1), additional_contact_name_a: "Erika UnitA",
      additional_contact_single: true, status: "confirmed")
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_issue: "HELP-123",
      deregistration_actual_compensation_cents: 15_000)
  end

  def path(action = nil) = ["/people/#{person.id}/deregistration", action].compact.join("/")

  def headers(accept = "application/json") = {"Accept" => accept, "X-Token" => token.plain_token}

  def json = JSON.parse(response.body)

  def error_codes = json["errors"].pluck("code")

  def api_post(action, body = {})
    post path(action), params: body.to_json, headers: headers.merge("Content-Type" => "application/json")
  end

  def make_form
    Wsjrdp2027::DeregistrationForm.new(person.reload).record_creation!
    Wsjrdp2027::DeregistrationFormDocument.new(person.reload, author: people(:admin), service_token: token).store!
    JSON.parse(Wsjrdp2027::DeregistrationState.new(person.reload).to_json)
  end

  def report(deregistration, message_id: "<1@worldscoutjamboree.de>")
    {"email_sent_at" => "2026-11-15T14:03:12+01:00", "email_to" => ["yp1.unita@wsjrdp.example.com"],
     "email_subject" => "WSJ27 Abmeldung", "email_message_id" => message_id, "deregistration" => deregistration}
  end

  def record(payload, klass: Wsjrdp2027::DeregistrationFormSent)
    klass.new(person.reload, payload, service_token: token).save!
  end

  describe "GET deregistration.json" do
    it "answers the deregistration" do
      get "#{path}.json", headers: headers

      expect(response).to have_http_status(200)
      expect(json).to include("person_id" => person.id, "deregistration_id" => person.reload.deregistration.id,
        "form_check" => {"errors" => [], "warnings" => []})
    end

    context "without people:log" do
      let(:scopes) { %w[people] }

      it "is refused" do
        get "#{path}.json", headers: headers

        expect(response).to have_http_status(403)
      end
    end
  end

  describe "POST prepare_form.json" do
    it "notes the deregistration with the API key, keeps the form and answers the deregistration" do
      with_versioning { api_post "prepare_form.json" }

      aggregate_failures do
        expect(response).to have_http_status(200)
        expect(json).to include("errors" => [], "warnings" => [])
        document = person.reload.deregistration.sent_form_document
        expect(json["deregistration"]).to include("status" => "deregistration_noted",
          "deregistration_status" => "form_created")
        expect(json["deregistration"]["form"]).to include("created_date" => Date.current.iso8601,
          "document_id" => document.id)
        expect(document).to have_attributes(origin: "api", origin_service_token: token)
        version = PaperTrail::Version.where(item: person, event: "update").last
        expect(version.changeset["status"]).to eq(%w[confirmed deregistration_noted])
        expect(version).to have_attributes(whodunnit: token.id.to_s, whodunnit_type: "ServiceToken")
      end
    end

    it "leaves a status that is under way, and a form made already" do
      person.update_columns(status: "deregistered")
      created = travel_to(Date.current - 2.days) { make_form["form"]["created_date"] }

      api_post "prepare_form.json"

      expect(json["deregistration"]).to include("status" => "deregistered")
      expect(json["deregistration"]["form"]["created_date"]).to eq(created)
    end

    it "refuses an incomplete form with every error and warning, and writes nothing" do
      person.update_columns(birthday: nil)
      person.update!(deregistration_actual_compensation_cents: nil, deregistration_issue: nil)

      api_post "prepare_form.json"

      expect(response).to have_http_status(422)
      expect(error_codes).to eq(%w[no_compensation no_birthday])
      expect(json["warnings"].pluck("code")).to eq(["no_issue"])
      expect(person.reload).to have_attributes(status: "confirmed", deregistration_form_created_date: nil)
    end

    it "answers 503 busy while the documents are busy" do
      allow(Wsjrdp::LockedChange).to receive(:run).and_raise(Wsjrdp::LockedChange::Busy, "busy")

      api_post "prepare_form.json"

      expect(response).to have_http_status(503)
      expect(error_codes).to eq(["busy"])
    end
  end

  describe "POST create_form.json" do
    it "makes the form and leaves the status" do
      api_post "create_form.json"

      expect(response).to have_http_status(200)
      expect(json["deregistration"]["form"]["created_date"]).to eq(Date.current.iso8601)
      expect(person.reload.status).to eq("confirmed")
    end
  end

  describe "GET form.pdf and form.png" do
    it "answers the kept PDF" do
      make_form

      get path("form.pdf"), headers: headers("application/pdf")

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body.b).to eq(pdf.b)
    end

    it "answers the kept picture" do
      make_form

      get path("form.png"), headers: headers("image/png")

      expect(response.media_type).to eq("image/png")
      expect(response.body.b).to eq(png)
    end

    it "answers 409 for a form not made yet" do
      get path("form.pdf"), headers: headers("application/pdf")

      expect(response).to have_http_status(409)
      expect(json["errors"]).to eq([{"code" => "form_not_created", "message" => "Das Abmelde-Formular ist noch nicht erzeugt."}])
    end
  end

  describe "POST form_sent.json" do
    it "answers 201 with the recorded mail and the deregistration" do
      api_post "form_sent.json", report(make_form)

      expect(response).to have_http_status(201)
      mailing = person.reload.deregistration_form_mailings.sole
      expect(json).to include("form_mailing" => mailing, "duplicate" => false)
      expect(json["deregistration"]["form_mailings"]).to eq([mailing])
    end

    it "answers 200 for a mail recorded already" do
      payload = report(make_form)
      record(payload)

      api_post "form_sent.json", payload

      expect(response).to have_http_status(200)
      expect(json["duplicate"]).to be(true)
    end

    it "answers a report it cannot record with the reason" do
      api_post "form_sent.json", report(make_form).except("email_to")

      expect(response).to have_http_status(422)
      expect(json["errors"]).to eq([{"code" => "invalid_report", "message" => "email_to is missing"}])
    end

    it "is the API key's only" do
      sign_in(people(:admin))

      post path("form_sent.json"), params: "{}", headers: {"Content-Type" => "application/json", "Accept" => "application/json"}

      expect(response).to have_http_status(403)
    end
  end

  describe "POST confirmation_sent.json" do
    it "answers 201 with the recorded confirmation" do
      person.update!(deregistration_kind: "termination")

      api_post "confirmation_sent.json", report(JSON.parse(Wsjrdp2027::DeregistrationState.new(person.reload).to_json))

      expect(response).to have_http_status(201)
      expect(json["confirmation_mailing"]).to include("email_subject" => "WSJ27 Abmeldung")
      expect(json["deregistration"]["confirmation_mailings"].size).to eq(1)
    end
  end
end
