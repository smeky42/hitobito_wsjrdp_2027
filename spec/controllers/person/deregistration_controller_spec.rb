# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The "Abmeldung" sub-tab of a person's Finanzen section
# (/people/:id/deregistration), gated on :log (doc/roles.md).
describe Person::DeregistrationController do
  let(:admin) { people(:admin) }
  let(:yp) { people(:yp_a_1) }
  let(:upload_root) { Pathname(Dir.mktmpdir("wsjrdp-deregistration")) }
  let(:kept_pdf) { "%PDF-1.4\n%kept\n" }
  let(:png) { "\x89PNG\r\n\x1a\nstub".b }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(upload_root)
    [Wsjrdp2027::DeregistrationForm, Wsjrdp2027::RefundReceipt].each do |document|
      allow_any_instance_of(document).to receive(:to_pdf).and_return(kept_pdf)
      allow_any_instance_of(document).to receive(:to_png).and_return(png)
    end
  end

  after { FileUtils.rm_rf(upload_root) }

  def book_payment(cents)
    AccountingEntry.create!(subject: yp, author: admin, amount_cents: cents, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  def kept_form = yp.reload.deregistration.sent_form_document

  def make_form!
    Wsjrdp2027::DeregistrationForm.new(yp.reload).record_creation!
    Wsjrdp2027::DeregistrationFormDocument.new(yp.reload, author: admin).store!
  end

  def stored(document) = File.binread(Wsjrdp2027::DocumentStore.path_for(document))

  def sent!
    yp.update!(deregistration_issue: "HELP-1", deregistration_form_created_date: Date.new(2026, 9, 27))
    yp.reload.deregistration.update!(form_sent_at: Time.zone.local(2026, 9, 28, 10), status: "form_sent")
  end

  def store_eml(number)
    row = yp.reload.deregistration
    Wsjrdp2027::DocumentStore.store!(StringIO.new("Message-ID: <#{number}@x>\r\n\r\nHallo\r\n"),
      {subject: yp, key: "deregistration", key_number: row.number, key_ref: row, secondary_key: "form_mail",
       secondary_key_number: number, filename: "Abmeldung #{number}.eml", author: admin}, upload: false)
  end

  context "as an admin" do
    before_all(setup_fixtures: true) { people(:yp_a_1).reload.update!(deregistration_effective_date: Date.new(2026, 10, 31)) }

    before { sign_in(admin) }

    describe "#show" do
      it "assigns the person, the group its sheet hangs below and the first section open" do
        get :show, params: {person_id: yp.id}

        expect(response).to be_successful
        expect(assigns(:person)).to eq(yp)
        expect(assigns(:group)).to eq(groups(:unit_a))
        expect(assigns(:dereg_open_sections)).to eq(%w[capture])
      end

      it "opens the known sections the session left open, in the page's order" do
        session[:deregistration_open_sections] = %w[receipt nonsense form]

        get :show, params: {person_id: yp.id}

        expect(assigns(:dereg_open_sections)).to eq(%w[form receipt])
      end

      it "opens nothing where the session closed everything" do
        session[:deregistration_open_sections] = []

        get :show, params: {person_id: yp.id}

        expect(assigns(:dereg_open_sections)).to eq([])
      end

      it "reads a stored value that is no list as nothing stored" do
        session[:deregistration_open_sections] = "creditor"

        get :show, params: {person_id: yp.id}

        expect(assigns(:dereg_open_sections)).to eq(%w[capture])
      end
    end

    describe "#sections" do
      it "remembers the open sections in the page's order, in the session only" do
        post :sections, params: {person_id: yp.id, sections: "receipt,form_preview,capture"}

        expect(response).to have_http_status(:no_content)
        expect(session[:deregistration_open_sections]).to eq(%w[capture form_preview receipt])
        expect(admin.reload.wsjrdp_user_preferences).not_to have_key("deregistration_open_sections")
      end

      it "remembers that everything is closed" do
        post :sections, params: {person_id: yp.id, sections: ""}

        expect(session[:deregistration_open_sections]).to eq([])
      end

      it "refuses a list with a section it does not know" do
        post :sections, params: {person_id: yp.id, sections: "capture,nonsense"}

        expect(response).to have_http_status(422)
        expect(session[:deregistration_open_sections]).to be_nil
      end

      it "refuses a request without a list" do
        post :sections, params: {person_id: yp.id}

        expect(response).to have_http_status(422)
      end
    end

    describe "#create_form" do
      it "stores the day, keeps the PDF with its picture and opens the form's section" do
        travel_to(Time.zone.local(2026, 9, 27, 12)) { post :create_form, params: {person_id: yp.id} }

        aggregate_failures do
          expect(response).to redirect_to(person_deregistration_path(yp))
          expect(flash[:notice]).to be_present
          expect(yp.reload.deregistration_form_created_date).to eq(Date.new(2026, 9, 27))
          expect(session[:deregistration_open_sections]).to include("form")
          expect(kept_form).to have_attributes(key: "deregistration", secondary_key: "form", origin: "ui",
            author: admin)
          expect(kept_form.derivatives.pluck(:derivation_key)).to eq(["thumbnail"])
        end
      end

      it "asks to try again while the documents are busy" do
        allow(Wsjrdp::LockedChange).to receive(:run).and_raise(Wsjrdp::LockedChange::Busy, "busy")

        post :create_form, params: {person_id: yp.id}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:alert]).to include("noch einmal")
      end
    end

    describe "#form" do
      it "sends a request back until the form is made" do
        get :form, params: {person_id: yp.id}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:alert]).to eq(I18n.t("people.deregistration_form.not_created"))
      end

      it "sends a request for a form it does not offer back, with the reason" do
        yp.update!(deregistration_kind: "termination")

        get :form, params: {person_id: yp.id}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:alert]).to include("Kündigung")
      end

      it "answers the kept PDF inline, so that nobody keeps it" do
        make_form!

        get :form, params: {person_id: yp.id}

        expect(response.media_type).to eq("application/pdf")
        expect(response.body.b).to eq(stored(kept_form))
        expect(response.headers["Content-Disposition"]).to start_with("inline")
        expect(response.headers["Cache-Control"]).to include("private", "no-store")
      end

      it "answers the kept picture" do
        make_form!

        get :form, params: {person_id: yp.id}, format: :png

        expect(response.media_type).to eq("image/png")
        expect(response.body.b).to eq(stored(kept_form.derivatives.sole))
      end

      it "draws the form from the data once the kept PDF is stale" do
        make_form!
        book_payment(100_00)
        allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_pdf).and_return("%PDF-1.4\n%drawn\n")

        get :form, params: {person_id: yp.id}

        expect(response.body).to eq("%PDF-1.4\n%drawn\n")
      end

      it "hands the PDF over as a file to save" do
        yp.update!(deregistration_form_created_date: Date.new(2026, 9, 27))

        get :form, params: {person_id: yp.id, download: "1"}

        expect(response.headers["Content-Disposition"]).to start_with("attachment")
      end
    end

    describe "#discard_form" do
      it "forgets the form, the receipt, the captured data and the fixed deadline, and keeps an entered one" do
        yp.update!(deregistration_form_created_date: Date.new(2026, 9, 27),
          deregistration_reply_due_date: Date.new(2026, 10, 11),
          deregistration_effective_reply_due_date: Date.new(2026, 10, 12),
          deregistration_receipt_created_date: Date.new(2026, 9, 27), deregistration_receipt_created_by_id: admin.id,
          deregistration_receipt_snapshot: {"amount_text" => "1,00 €"},
          deregistration_refund_iban: "DE02120300000000202051", deregistration_person_role: "YP")

        post :discard_form, params: {person_id: yp.id}

        aggregate_failures do
          expect(response).to redirect_to(person_deregistration_path(yp))
          expect(flash[:notice]).to be_present
          expect(yp.reload).to have_attributes(deregistration_form_created_date: nil,
            deregistration_effective_reply_due_date: nil, deregistration_reply_due_date: Date.new(2026, 10, 11),
            deregistration_receipt_created_date: nil, deregistration_receipt_snapshot: nil,
            deregistration_refund_iban: nil)
        end
      end

      it "hides the kept PDF and its picture, keeping their files" do
        make_form!
        kept = kept_form

        post :discard_form, params: {person_id: yp.id}

        expect(kept.reload.status).to eq(WsjrdpDocument::DELETED)
        expect(kept.derivatives.pluck(:status)).to eq([WsjrdpDocument::DELETED])
        expect(File.file?(Wsjrdp2027::DocumentStore.path_for(kept))).to be(true)
        expect(yp.reload.deregistration.sent_form_document_id).to be_nil
      end

      it "discards the form while the documents are busy, no longer listing its PDF" do
        make_form!
        kept = kept_form
        allow(Wsjrdp::LockedChange).to receive(:run).and_raise(Wsjrdp::LockedChange::Busy, "busy")

        post :discard_form, params: {person_id: yp.id}

        expect(yp.reload.deregistration_form_created_date).to be_nil
        expect(kept.reload.status).to eq(WsjrdpDocument::CURRENT)
        expect(Wsjrdp2027::DeregistrationFormDocument.documents_of(yp)).to be_empty
      end

      it "waits for a report of the deregistration and discards nothing while it runs" do
        yp.update!(deregistration_form_created_date: Date.new(2026, 9, 27))
        stub_const("Wsjrdp2027::DeregistrationFormSent::REPORT_LOCK_TIMEOUT", 0.seconds)

        holding_session_lock(Wsjrdp2027::DeregistrationFormSent.report_lock_key(yp.reload.deregistration)) do
          post :discard_form, params: {person_id: yp.id}
        end

        expect(flash[:alert]).to include("noch einmal")
        expect(yp.reload.deregistration_form_created_date).to be_present
      end

      it "refuses to discard a form a report marked sent since the row was read" do
        make_form!
        row = yp.reload.deregistration
        allow(Wsjrdp2027::DeregistrationFormSent).to receive(:with_report_lock).and_wrap_original do |m, r, &b|
          WsjrdpDeregistration.where(id: row.id).update_all(form_sent_at: Time.current, status: "form_sent")
          m.call(r, &b)
        end

        post :discard_form, params: {person_id: yp.id}

        expect(flash[:alert]).to be_present
        expect(row.reload).to have_attributes(status: "form_sent", sent_form_document_id: row.sent_form_document_id)
      end

      it "refuses to discard a sent form" do
        sent!

        post :discard_form, params: {person_id: yp.id}

        expect(flash[:alert]).to eq(I18n.t("people.deregistration.fixed"))
        expect(yp.reload.deregistration_form_created_date).to eq(Date.new(2026, 9, 27))
      end
    end

    describe "#new_version" do
      it "makes the next version of a sent form, the old one superseded" do
        sent!

        post :new_version, params: {person_id: yp.id}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(yp.reload.deregistration).to have_attributes(number: 2, status: "recorded", issue: "HELP-1",
          form_snapshot: {})
      end

      it "makes no new version of a row that is still open for changes" do
        post :new_version, params: {person_id: yp.id}

        expect(flash[:alert]).to be_present
        expect(WsjrdpDeregistration.where(person_id: yp.id).count).to eq(1)
      end
    end

    describe "the receipt" do
      it "sends a request back until it is made" do
        get :refund_receipt, params: {person_id: yp.id}, format: :png

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:alert]).to eq(I18n.t("people.refund_receipt.not_created"))
      end

      it "answers the made receipt as a PDF, inline" do
        yp.update!(deregistration_receipt_created_date: Date.new(2026, 9, 27))

        get :refund_receipt, params: {person_id: yp.id}

        expect(response.media_type).to eq("application/pdf")
        expect(response.headers["Content-Disposition"]).to start_with("inline")
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "stores the day and the maker and opens the receipt's section" do
        travel_to(Time.zone.local(2026, 9, 27, 12)) { post :create_receipt, params: {person_id: yp.id} }

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(yp.reload).to have_attributes(deregistration_receipt_created_date: Date.new(2026, 9, 27),
          deregistration_receipt_created_by_id: admin.id)
        expect(session[:deregistration_open_sections]).to include("receipt")
      end

      it "is discarded alone, the captured data staying while the form says them" do
        yp.update!(deregistration_form_created_date: Date.new(2026, 9, 27),
          deregistration_receipt_created_date: Date.new(2026, 9, 27), deregistration_receipt_created_by_id: admin.id,
          deregistration_refund_iban: "DE02120300000000202051", deregistration_person_role: "YP")

        post :discard_receipt, params: {person_id: yp.id}

        expect(yp.reload).to have_attributes(deregistration_receipt_created_date: nil,
          deregistration_receipt_created_by_id: nil, deregistration_refund_iban: "DE02120300000000202051")
      end
    end

    describe "#mail_file" do
      it "downloads a mail as the EML under its file name" do
        mail = store_eml(1)

        get :mail_file, params: {person_id: yp.id, document_id: mail.id}

        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Disposition"]).to start_with("attachment")
          .and include('filename="Abmeldung 1.eml"')
        expect(response.body).to include("Message-ID: <1@x>")
      end

      it "downloads no other document" do
        make_form!

        get :mail_file, params: {person_id: yp.id, document_id: kept_form.id}

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "#update" do
      def update(person, **extra) = put(:update, params: {person_id: yp.id, person: person, **extra})

      it "saves the changes, ignores status and finance status, and leads back to the page" do
        status, sepa_status = yp.status, yp.sepa_status

        update({deregistration_issue: "Ticket 1", status: "deregistered", sepa_status: "missing"})

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(yp.reload).to have_attributes(deregistration_issue: "Ticket 1", status: status, sepa_status: sepa_status)
      end

      it "honours the return_url the form carries" do
        update({deregistration_issue: "Ticket 3"}, return_url: person_fee_path(yp))

        expect(response).to redirect_to(person_fee_path(yp))
      end

      it "leads back to the form where the save is to go on" do
        update({deregistration_issue: "Ticket 4"}, stay: "1")

        expect(response).to redirect_to(edit_person_deregistration_path(yp))
      end

      it "names each changed field with its previous value, in the order of the form" do
        yp.update!(deregistration_issue: "Ticket 1")

        update({deregistration_issue: "Ticket 1", deregistration_actual_compensation_eur: "150",
                deregistration_effective_date: "2026-03-01"})

        expect(flash[:notice]).to eq(["Angaben zur Abmeldung angepasst:", "Entschädigung: – → 150,— €",
          "Abmeldung zum: 31.10.2026 → 01.03.2026"])
      end

      it "names a field that was cleared" do
        yp.update!(deregistration_issue: "Ticket 1")

        update({deregistration_issue: ""})

        expect(yp.reload.deregistration_issue).to be_nil
        expect(flash[:notice]).to include("Ticket Abmeldung: Ticket 1 → –")
      end

      it "names the kind, the default as its previous value, and the request date after the new kind" do
        update({deregistration_kind: "termination", deregistration_requested_date: "01.09.2026"})

        expect(flash[:notice]).to include("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)",
          "Gekündigt am: – → 01.09.2026")
      end

      it "says nothing changed for an unchanged value" do
        yp.update!(deregistration_issue: "Ticket 1")

        update({deregistration_issue: "Ticket 1"})

        expect(flash[:notice]).to eq(described_class::NO_CHANGE_NOTICE)
      end

      it "says nothing changed when the form sends the defaults again, and stores none of them" do
        update({deregistration_kind: "withdrawal", deregistration_form_show_contractual_compensation: "1",
                deregistration_refund_receipt_text: "", deregistration_refund_receipt_show_default_explanation: "1"})

        expect(flash[:notice]).to eq(described_class::NO_CHANGE_NOTICE)
        expect(yp.reload.deregistration.receipt).to eq({})
      end

      it "stores an unchecked flag as an explicit off and names it" do
        update({deregistration_form_show_contractual_compensation: "0",
                deregistration_refund_receipt_show_default_explanation: "0"})

        row = yp.reload.deregistration
        expect(row.show_contractual_compensation).to be(false)
        expect(row.receipt["show_default_explanation"]).to be(false)
        expect(flash[:notice]).to include("Entschädigung nach T&R im Abmelde-Formular: anzeigen → ausblenden",
          "Erklärungsabsatz im Beleg: anzeigen → ausblenden")
      end

      it "removes a flag that is checked again" do
        yp.update!(deregistration_refund_receipt_show_default_explanation: false)

        update({deregistration_refund_receipt_show_default_explanation: "1"})

        expect(yp.reload.deregistration.receipt).to eq({})
        expect(flash[:notice]).to include("Erklärungsabsatz im Beleg: ausblenden → anzeigen")
      end

      it "leaves a flag alone where the form sends none" do
        yp.update!(deregistration_refund_receipt_show_default_explanation: false)

        update({deregistration_issue: "Ticket 1"})

        expect(yp.reload.deregistration.receipt).to eq("show_default_explanation" => false)
      end

      it "refuses a kind outside the three and saves nothing" do
        update({deregistration_kind: "foo"})

        expect(response).to have_http_status(:bad_request)
        expect(yp.reload.deregistration_kind).to eq("withdrawal")
      end

      it "refuses a date that is no date and saves nothing" do
        update({deregistration_effective_date: "kein Datum"})

        expect(response).to have_http_status(:bad_request)
        expect(yp.reload.deregistration_effective_date).to eq(Date.new(2026, 10, 31))
      end
    end

    it "routes the writing actions as POST and the documents as GET only" do
      aggregate_failures do
        %i[sections create_form discard_form].each do |action|
          path = public_send(:"#{action}_person_deregistration_path", yp)
          expect(post: path).to be_routable
          expect(get: path).not_to be_routable
        end
        %i[form refund_receipt].each do |action|
          expect(post: public_send(:"#{action}_person_deregistration_path", yp)).not_to be_routable
        end
      end
    end

    # A controller spec cannot send the :id spelling: Rails builds the path
    # from the params before the request runs.
    it "maps an :id param to :person_id" do
      controller.params = ActionController::Parameters.new(id: yp.id.to_s)
      controller.send(:map_id_to_person_id)

      expect(controller.params[:person_id]).to eq(yp.id.to_s)
      expect(controller.send(:person)).to eq(yp)
    end

    describe "the page" do
      render_views

      def page = Nokogiri::HTML(response.body)

      def summary_labels = page.css("#dereg-summary dt").map { |dt| dt.text.strip }

      def summary_text = page.css("#dereg-summary").text.squish

      def form_section = page.at_css("#dereg-section-form")

      def thumb(key) = page.at_css("#dereg-section-#{key} img.dereg-doc-thumb")

      def frame(key) = page.at_css("#dereg-section-#{key}_preview iframe.dereg-doc-frame")

      it "offers to make the form, warning while no compensation is entered" do
        get :show, params: {person_id: yp.id}

        aggregate_failures do
          expect(summary_labels).not_to include(I18n.t("people.deregistration_summary.ticket"))
          expect(summary_text).to include(I18n.t("people.deregistration_summary.reply_due_default"))
          expect(page.at_css("#deregistration_form_no_compensation")).to be_present
          create = form_section.at_css("form[action='#{create_form_person_deregistration_path(yp)}']")
          expect(create["data-dereg-confirm"]).to eq(I18n.t("people.deregistration_form.no_compensation_confirm"))
          expect(form_section.at_css(".dereg-doc-thumb-empty")).to be_present
          expect(frame("form")).to be_nil
          expect(page.at_css("#dereg-fixed")).to be_nil
        end
      end

      it "fetches the documents of the open sections only, and lists the kept form and its mails" do
        book_payment(10_000)
        yp.update!(deregistration_issue: "T1", deregistration_actual_compensation_cents: 50_000,
          deregistration_effective_reply_due_date: Date.new(2026, 10, 11),
          deregistration_receipt_created_date: Date.new(2026, 9, 27), deregistration_receipt_created_by_id: admin.id)
        make_form!
        mail = store_eml(1)
        session[:deregistration_open_sections] = %w[form form_preview receipt_preview]

        get :show, params: {person_id: yp.id}

        aggregate_failures do
          expect(summary_labels).to include(I18n.t("people.deregistration_summary.ticket"),
            I18n.t("people.deregistration_summary.claim"))
          expect(summary_text).to include(I18n.t("people.deregistration_summary.reply_due_fixed"))
          expect(page.at_css("#deregistration_form_no_compensation")).to be_nil
          expect(form_section.at_css("form[action='#{discard_form_person_deregistration_path(yp)}']")).to be_present
          expect(thumb("form")["src"]).to eq(form_person_deregistration_path(yp, format: :png))
          expect(frame("form")["src"]).to eq(form_person_deregistration_path(yp))
          expect(thumb("receipt")["src"]).to be_nil
          expect(frame("receipt")["src"]).to be_nil
          expect(page.css("#deregistration_form_documents .deregistration-form-document").size).to eq(2)
          expect(page.css("#deregistration_form_documents a").pluck("href"))
            .to include(mail_file_person_deregistration_path(yp, document_id: mail.id))
        end
      end

      it "locks a sent form, offering a new version instead of a discard or the form" do
        sent!

        get :show, params: {person_id: yp.id}

        aggregate_failures do
          expect(page.at_css("#dereg-fixed form[action='#{new_version_person_deregistration_path(yp)}']")).to be_present
          expect(page.at_css("form[action='#{discard_form_person_deregistration_path(yp)}']")).to be_nil
          expect(page.at_css("a[href='#{edit_person_deregistration_path(yp)}']")).to be_nil
        end
      end

      it "says why there is no form instead of offering it, and offers the receipt all the same" do
        yp.update!(deregistration_kind: "termination")

        get :show, params: {person_id: yp.id}

        aggregate_failures do
          expect(page.at_css("#deregistration_form_hint").text).to include("Kündigung")
          expect(form_section.at_css(".dereg-doc-row")).to be_nil
          expect(page.at_css("#dereg-section-receipt .dereg-doc-row")).to be_present
        end
      end

      it "edits in the capture frame, the flags checked while nothing is stored" do
        get :edit, params: {person_id: yp.id}

        frame = page.at_css("turbo-frame#deregistration_capture")
        aggregate_failures do
          expect(frame.at_css("select[name='person[deregistration_kind]'] option[selected]")["value"]).to eq("withdrawal")
          %w[deregistration_form_show_contractual_compensation
            deregistration_refund_receipt_show_default_explanation].each do |attr|
            expect(frame.at_css("input[type=checkbox][name='person[#{attr}]']")["checked"]).to be_present
          end
          expect(frame.at_css("[name='person[status]'], [name='person[sepa_status]']")).to be_nil
        end
      end

      describe "a save from the frame" do
        def streams = page.css("turbo-stream").to_h { |s| [s["target"], s] }

        def save(person, **extra)
          put :update, params: {person_id: yp.id, person: person, **extra}, format: :turbo_stream
        end

        it "answers the head, the read-only capture, both documents as they now stand and the flash" do
          yp.update!(deregistration_effective_date: nil)

          save({deregistration_effective_date: "2026-12-31"})

          aggregate_failures do
            expect(page.css("turbo-stream").map { |s| [s["action"], s["target"]] }).to eq([
              ["replace", "dereg-summary"], ["update", "deregistration_capture"], ["update", "dereg-form-body"],
              ["update", "dereg-receipt-body"], ["update", "flash"]
            ])
            expect(streams["deregistration_capture"].at_css("form")).to be_nil
            expect(streams["dereg-form-body"].at_css("form[action='#{create_form_person_deregistration_path(yp)}']"))
              .to be_present
          end
        end

        it "hands the form back where the save is to go on" do
          save({deregistration_issue: "Ticket 1"}, stay: "1")

          expect(streams["deregistration_capture"].at_css("input[name='person[deregistration_issue]']")["value"])
            .to eq("Ticket 1")
        end

        it "brings the form back alone where the model refused the values" do
          save({deregistration_kind: "foo"})

          expect(response).to have_http_status(422)
          expect(streams.keys).to eq(["deregistration_capture"])
          expect(streams["deregistration_capture"].at_css("#error_explanation")).to be_present
        end
      end
    end
  end

  context "as a unit leader" do
    before { sign_in(people(:ul_a_1)) }

    {show: :get, edit: :get, form: :get, refund_receipt: :get, sections: :post, update: :put}.each do |action, verb|
      it "is refused #{action}" do
        expect { public_send(verb, action, params: {person_id: yp.id}) }.to raise_error(CanCan::AccessDenied)
      end
    end
  end
end
