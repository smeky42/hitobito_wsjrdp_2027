# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The "Abmeldung" sub-tab of a person's Finanzen section
# (/people/:id/deregistration). It reads like the Status and Medizin tabs -- a
# read-only page whose toolbar leads to the form -- and all three actions are
# gated on :log, the wagon's "privileged view" (doc/roles.md), which a unit
# leader does not hold.
describe Person::DeregistrationController do
  render_views

  let(:admin) { people(:admin) }
  let(:yp) { people(:yp_a_1) }

  def sub_nav_of(doc, href)
    doc.css("ul.nav-sub").find do |ul|
      ul.css("a").any? { |a| a["href"] == href }
    end
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "renders the page read-only, with an edit button and no form" do
      get :show, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(response.body).to include("Ticket Abmeldung")

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("a").pluck("href"))
        .to include(edit_person_deregistration_path(yp))
      expect(doc.css("form input[name='person[deregistration_issue]']")).to be_empty
    end

    # Who ended the participation is the first thing the page says. The key is
    # absent for everyone who was there before the flag existed, and that reads
    # as a withdrawal.
    it "leads with the kind, a withdrawal while the key is absent" do
      get :show, params: {person_id: yp.id}

      first_list = Nokogiri::HTML(response.body).css("#main dl").first
      expect(first_list.css("dt").first.text.strip).to eq("Art")
      expect(first_list.css("dd").first.text.strip).to eq("Abmeldung (durch die Person)")
    end

    it "names a termination as one" do
      yp.update!(deregistration_kind: "termination")

      get :show, params: {person_id: yp.id}

      first_list = Nokogiri::HTML(response.body).css("#main dl").first
      expect(first_list.css("dd").first.text.strip).to eq("Kündigung (durch das Kontingent)")
    end

    it "offers both kinds on the form, the withdrawal preselected" do
      get :edit, params: {person_id: yp.id}

      select = Nokogiri::HTML(response.body)
        .css("select[name='person[deregistration_kind]']").first
      expect(select).to be_present
      expect(select.css("option").pluck("value")).to eq(%w[withdrawal termination])
      expect(select.css("option[selected]").pluck("value")).to eq(["withdrawal"])
    end

    it "names the kind in the flash, with the default as the previous value" do
      put :update, params: {person_id: yp.id, person: {deregistration_kind: "termination"}}

      expect(yp.reload.deregistration_kind).to eq("termination")
      expect(flash[:notice])
        .to include("Art: Abmeldung (durch die Person) → Kündigung (durch das Kontingent)")
    end

    it "refuses a kind outside the two and re-renders the form" do
      put :update, params: {person_id: yp.id, person: {deregistration_kind: "foo"}}

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("person[deregistration_kind]")
      expect(yp.reload.deregistration_kind).to be_nil
    end

    # The refund belongs with the amount it comes out of, above the line the
    # next list draws -- not below the T&R bracket.
    it "shows the refund right after the compensation" do
      AccountingEntry.create!(subject: yp, author: admin, amount_cents: 10_000,
        amount_currency: "EUR", description: "Teilnahmebeitrag",
        value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
      yp.update!(deregistration_actual_compensation_cents: 5_000)

      get :show, params: {person_id: yp.id}

      main = Nokogiri::HTML(response.body).css("#main").text
      expect(main).to include("Rückzahlung", "Entschädigung nach T&R")
      expect(main.index("Rückzahlung")).to be < main.index("Entschädigung nach T&R")
    end

    # What the finance team types into Moss comes first: the creditor the
    # refund is paid to, then the receipt it is paid from.
    it "leads the receipt with the creditor section" do
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      headings = doc.css("h3").map { |h| h.text.strip }
      expect(headings.find { |h| h.start_with?("Kreditor für Rückzahlung") }).to be_present
      creditor_at = doc.css("#main").text.index("Kreditor für Rückzahlung")
      receipt_at = doc.css("#main").text.index("Moss-Beleg Rückzahlung")
      expect(creditor_at).to be < receipt_at

      labels = doc.css("#main dt").map { |dt| dt.text.strip }
      expect(labels).to include("Name", "Standard-Sachkonto", "Standard Kostenstelle",
        "Standard Sphäre", "Standard-Team", "Land der Empfängerbank", "IBAN",
        "Name des Kontoinhabers", "Standard-Zahlungsmethode", "Land",
        "Straße und Hausnummer", "Postleitzahl", "Ort")
      expect(doc.css("#main dd").map { |dd| dd.text.strip })
        .to include("TN #{yp.id}", "41030 Teilnehmendenbeiträge", "Banküberweisung")
    end

    # An address the parser had to guess at gets a warning, with the line as it
    # was typed in the tooltip.
    it "flags an address that needed a heuristic" do
      yp.update!(sepa_address: "Musterweg 12 12345 Musterstadt")

      get :show, params: {person_id: yp.id}

      warning = Nokogiri::HTML(response.body).css("#main .text-warning").first
      expect(warning).to be_present
      expect(warning.text).to include("Adresse automatisch zerlegt", "ohne Komma")
      expect(warning["title"]).to eq("Musterweg 12 12345 Musterstadt")
    end

    it "leaves a plain address unflagged" do
      yp.update!(sepa_address: "Musterweg 1a, 12345 Musterstadt")

      get :show, params: {person_id: yp.id}

      expect(Nokogiri::HTML(response.body).css("#main .text-warning")).to be_empty
    end

    # The country of the address is Germany unless the address says otherwise.
    it "names Deutschland as the creditor's country" do
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      rows = doc.css("#main dt").map { |dt| dt.text.strip }
        .zip(doc.css("#main dd").map { |dd| dd.text.strip })
      expect(rows).to include(["Land", "Deutschland"])
    end

    # A German IBAN needs no BIC, and most of these carry none -- so the row is
    # there only where there is something to show.
    it "shows the BIC row only where a BIC is stored" do
      get :show, params: {person_id: yp.id}
      expect(Nokogiri::HTML(response.body).css("#main dt").map { |dt| dt.text.strip })
        .not_to include("BIC")

      yp.update!(sepa_bic: "genode61abc")
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("#main dt").map { |dt| dt.text.strip }).to include("BIC")
      expect(doc.css("#main dd").map { |dd| dd.text.strip }).to include("GENODE61ABC")
    end

    it "links to where those creditors are kept in Moss" do
      get :show, params: {person_id: yp.id}

      link = Nokogiri::HTML(response.body).css("a")
        .find { |a| a["href"] == "https://getmoss.com/app/accounting/suppliers" }
      expect(link).to be_present
      expect(link["target"]).to eq("_blank")
      expect(link.text).to include("Kreditoren in Moss")
    end

    # The receipt has a section of its own at the bottom of the page: what it
    # will say, and the text it says above its table.
    it "previews the receipt and offers its form" do
      groups(:unit_a).update!(additional_info: {"group_code" => "A1"})

      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("h3").map { |h| h.text.strip }).to include("Moss-Beleg Rückzahlung")
      labels = doc.css("#main dt").map { |dt| dt.text.strip }
      expect(labels).to include("Team/Unit", "Rolle", "Beitrag", "Bisher bezahlt",
        "Buchungstext", "Verwendungszweck", "Kontoinhaber", "IBAN")
      expect(doc.css("#main").text).to include("A1", "Youth Participant in einer Unit")
    end

    # The fee names its own reduction where there is one.
    it "names the reduction in the fee label" do
      yp.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "rdp Delegate")

      get :show, params: {person_id: yp.id}

      labels = Nokogiri::HTML(response.body).css("#main dt").map { |dt| dt.text.strip }
      expect(labels).to include("Beitrag (rdp Delegate)")
      expect(labels).not_to include("Beitrag")
    end

    # The unit belongs to the receipt, not to the list the page leads with.
    it "leaves the first list as it was" do
      get :show, params: {person_id: yp.id}

      first_list = Nokogiri::HTML(response.body).css("#main dl").first
      expect(first_list.css("dt").map { |dt| dt.text.strip }).not_to include("Team/Unit")
    end

    it "carries the text field, the disabled save button and the pdf button" do
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      form = doc.css("form#refund_receipt_form").first
      expect(form["action"]).to eq(refund_receipt_person_deregistration_path(yp))
      expect(form["method"]).to eq("post")

      field = form.css("textarea[name='person[deregistration_refund_receipt_text]']").first
      expect(field).to be_present
      expect(field.text.strip).to eq("")
      expect(field["placeholder"]).to eq("Optionaler Text vor dem Erklärungsabsatz")

      box = form.css("input#refund_receipt_explanation").first
      expect(box["type"]).to eq("checkbox")
      expect(box["checked"]).to be_present
      expect(form.css("input[type=hidden][name='person[deregistration_refund_receipt_show_default_explanation]']"))
        .to be_present

      save_button = form.css("input#refund_receipt_text_submit").first
      expect(save_button["value"]).to eq("Text speichern")
      expect(save_button["disabled"]).to be_present
      expect(save_button["formaction"]).to eq(refund_receipt_text_person_deregistration_path(yp))

      pdf_button = form.css("button#refund_receipt_submit").first
      expect(pdf_button["formtarget"]).to eq("_blank")
      expect(pdf_button.text).to include("Moss-Beleg Rückzahlung")
    end

    # One form, two actions: with per_form_csrf_tokens on, a token bound to the
    # form's own action is refused by the other one. The form therefore carries
    # the session-global token, and both buttons get through with it.
    context "with forgery protection on" do
      around do |example|
        was = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
        ActionController::Base.allow_forgery_protection = was
      end

      def form_token
        get :show, params: {person_id: yp.id}
        Nokogiri::HTML(response.body)
          .css("form#refund_receipt_form input[name=authenticity_token]").first["value"]
      end

      it "takes the form's token on the way to the text action" do
        token = form_token

        post :refund_receipt_text, params: {person_id: yp.id, authenticity_token: token,
                                            person: {deregistration_refund_receipt_text: "Hallo Team"}}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(yp.reload.deregistration_refund_receipt_text).to eq("Hallo Team")
      end

      it "takes the same token on the way to the receipt itself" do
        token = form_token

        post :refund_receipt, params: {person_id: yp.id, authenticity_token: token,
                                       person: {deregistration_refund_receipt_text: "Hallo Team"}}

        expect(response).to be_successful
        expect(response.body).to start_with("%PDF")
      end
    end

    it "keeps the toolbar down to the edit button" do
      get :show, params: {person_id: yp.id}

      hrefs = Nokogiri::HTML(response.body).css("a").pluck("href")
      expect(hrefs).to include(edit_person_deregistration_path(yp))
      expect(hrefs.select { |href| href.to_s.include?("refund_receipt") }).to be_empty
    end

    it "unchecks the box where the paragraph was switched off" do
      yp.update!(deregistration_refund_receipt_show_default_explanation: false)

      get :show, params: {person_id: yp.id}

      box = Nokogiri::HTML(response.body).css("input#refund_receipt_explanation").first
      expect(box["checked"]).to be_nil
    end

    it "stores the switched-off paragraph" do
      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_show_default_explanation: "0"}}

      expect(yp.reload.additional_info["deregistration_refund_receipt_show_default_explanation"])
        .to be(false)
      expect(flash[:notice]).to eq("Text im Beleg gespeichert")
    end

    # Shown is the default, and the default is an absent key.
    it "removes the key when the box is checked again" do
      yp.update!(deregistration_refund_receipt_show_default_explanation: false)

      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_show_default_explanation: "1"}}

      expect(yp.reload.additional_info)
        .not_to have_key("deregistration_refund_receipt_show_default_explanation")
    end

    it "leaves the flag alone where the form sends none" do
      yp.update!(deregistration_refund_receipt_show_default_explanation: false)

      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_text: "Hallo Team"}}

      expect(yp.reload.additional_info["deregistration_refund_receipt_show_default_explanation"])
        .to be(false)
      expect(yp.deregistration_refund_receipt_text).to eq("Hallo Team")
    end

    it "shows a stored text in the field" do
      yp.update!(deregistration_refund_receipt_text: "Hallo Team")

      get :show, params: {person_id: yp.id}

      field = Nokogiri::HTML(response.body)
        .css("textarea[name='person[deregistration_refund_receipt_text]']").first
      expect(field.text.strip).to eq("Hallo Team")
    end

    it "answers with the pdf and saves the text on the way" do
      post :refund_receipt, params: {person_id: yp.id,
                                     person: {deregistration_refund_receipt_text: "Hallo Team"}}

      expect(response).to be_successful
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
      expect(response.headers["Content-Disposition"]).to start_with("inline")
      expect(response.headers["Content-Disposition"]).to include("R%C3%BCckzahlung.pdf")
      expect(yp.reload.deregistration_refund_receipt_text).to eq("Hallo Team")
    end

    it "leaves a stored text alone when the form sends none" do
      yp.update!(deregistration_refund_receipt_text: "Hallo Team")

      post :refund_receipt, params: {person_id: yp.id}

      expect(response.body).to start_with("%PDF")
      expect(yp.reload.deregistration_refund_receipt_text).to eq("Hallo Team")
    end

    it "saves the text on its own and returns to the page" do
      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_text: "Hallo Team"}}

      expect(response).to redirect_to(person_deregistration_path(yp))
      expect(flash[:notice]).to eq("Text im Beleg gespeichert")
      expect(yp.reload.deregistration_refund_receipt_text).to eq("Hallo Team")
    end

    it "says so when the text did not change" do
      yp.update!(deregistration_refund_receipt_text: "Hallo Team")

      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_text: "Hallo Team"}}

      expect(flash[:notice]).to eq("Text im Beleg nicht verändert")
    end

    # An emptied field is no text at all, and the default greeting comes back.
    it "drops the key when the text is emptied" do
      yp.update!(deregistration_refund_receipt_text: "Hallo Team")

      post :refund_receipt_text, params: {person_id: yp.id,
                                          person: {deregistration_refund_receipt_text: ""}}

      expect(yp.reload.additional_info).not_to have_key("deregistration_refund_receipt_text")
      expect(flash[:notice]).to eq("Text im Beleg gespeichert")
    end

    # Both receipt actions write, so neither is reachable with a GET.
    it "has no GET for the receipt" do
      expect(post: refund_receipt_person_deregistration_path(yp)).to be_routable
      expect(get: refund_receipt_person_deregistration_path(yp)).not_to be_routable
      expect(post: refund_receipt_text_person_deregistration_path(yp)).to be_routable
      expect(get: refund_receipt_text_person_deregistration_path(yp)).not_to be_routable
    end

    it "shows all three finance sub-tabs with Abmeldung active" do
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      sub_nav = sub_nav_of(doc, person_deregistration_path(yp))
      expect(sub_nav).to be_present
      expect(sub_nav.css("a").pluck("href")).to include(person_fee_path(yp),
        person_spend_path(yp), person_deregistration_path(yp))
      expect(sub_nav.css("li.active a").pluck("href"))
        .to eq([person_deregistration_path(yp)])
    end

    it "assigns the person and the group its sheet hangs below" do
      get :show, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(assigns(:person)).to eq(yp)
      expect(assigns(:group)).to eq(groups(:unit_a))
    end

    # The route spells the key :person_id; PersonInPrimaryGroup accepts an :id
    # given instead. A controller spec cannot send that spelling -- Rails
    # generates the path from the params before the request runs -- so the
    # callback is asserted on its own.
    it "maps an :id param to :person_id" do
      controller.params = ActionController::Parameters.new(id: yp.id.to_s)
      controller.send(:map_id_to_person_id)

      expect(controller.params[:person_id]).to eq(yp.id.to_s)
      expect(controller.send(:person)).to eq(yp)
    end

    it "renders the form on edit, cancelling back to the page" do
      get :edit, params: {person_id: yp.id}

      expect(response).to be_successful
      doc = Nokogiri::HTML(response.body)
      expect(doc.css("form input[name='person[deregistration_issue]']")).to be_present
      expect(doc.css("a").pluck("href")).to include(person_deregistration_path(yp))
    end

    it "saves the changes and redirects to the page" do
      put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}}

      expect(response).to redirect_to(person_deregistration_path(yp))
      expect(yp.reload.deregistration_issue).to eq("Ticket 1")
    end

    # The flash partial renders an array as one line each, so the notice names
    # every field the save touched.
    it "names each changed field in the flash" do
      put :update, params: {person_id: yp.id,
                            person: {deregistration_issue: "Ticket 1",
                                     deregistration_effective_date: "2026-02-15"}}

      expect(yp.reload.deregistration_effective_date).to eq(Date.new(2026, 2, 15))
      expect(flash[:notice]).to be_a(Array)
      expect(flash[:notice]).to include("Angaben zur Abmeldung angepasst:",
        "Ticket Abmeldung: – → Ticket 1",
        "Abmeldung zum: – → 15.02.2026")
    end

    it "names the previous value and leaves an unchanged field out" do
      yp.update!(deregistration_issue: "Ticket 1",
        deregistration_effective_date: Date.new(2026, 2, 15))

      put :update, params: {person_id: yp.id,
                            person: {deregistration_issue: "Ticket 1",
                                     deregistration_effective_date: "2026-03-01",
                                     deregistration_actual_compensation_eur: "150"}}

      expect(flash[:notice]).to include("Abmeldung zum: 15.02.2026 → 01.03.2026",
        "Entschädigung: – → 150,— €")
      expect(flash[:notice].grep(/Ticket Abmeldung/)).to be_empty
    end

    # Clearing the last remaining field empties the jsonb column, which used to
    # read as "no change at all".
    it "names a field that was cleared to empty" do
      yp.update!(deregistration_issue: "Ticket 1")

      put :update, params: {person_id: yp.id, person: {deregistration_issue: ""}}

      expect(yp.reload.deregistration_issue).to be_nil
      expect(flash[:notice]).to include("Ticket Abmeldung: Ticket 1 → –")
    end

    it "says so when nothing changed" do
      yp.update!(deregistration_issue: "Ticket 1")

      put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}}

      expect(response).to redirect_to(person_deregistration_path(yp))
      expect(flash[:notice]).to eq("Angaben zur Abmeldung wurden nicht verändert")
    end

    # One redirect for every format: Turbo submits the form as POST with
    # _method=put and follows it with a full visit, so the saved form leaves
    # the edit page without a turbo_stream action of its own.
    it "redirects a turbo_stream update to the page as well" do
      put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 2"}},
        format: :turbo_stream

      expect(response).to redirect_to(person_deregistration_path(yp))
      expect(yp.reload.deregistration_issue).to eq("Ticket 2")
    end

    it "honours the return_url the form carries" do
      put :update, params: {person_id: yp.id, return_url: person_fee_path(yp),
                            person: {deregistration_issue: "Ticket 3"}}

      expect(response).to redirect_to(person_fee_path(yp))
      expect(yp.reload.deregistration_issue).to eq("Ticket 3")
    end
  end

  context "as a unit leader" do
    before { sign_in(people(:ul_a_1)) }

    it "refuses the page" do
      expect { get :show, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the form" do
      expect { get :edit, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the receipt" do
      expect { post :refund_receipt, params: {person_id: yp.id} }
        .to raise_error(CanCan::AccessDenied)
    end

    it "refuses to save the receipt text" do
      expect { post :refund_receipt_text, params: {person_id: yp.id} }
        .to raise_error(CanCan::AccessDenied)
    end
  end
end
