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
# read-only page with a link to the form -- and every action is gated on :log,
# the wagon's "privileged view" (doc/roles.md), which a unit leader does not
# hold.
#
# The page is a summary head above four collapsible sections, two of which
# preview their document in a collapsible of its own; which of them stand open is
# remembered per login user.
describe Person::DeregistrationController do
  render_views

  let(:admin) { people(:admin) }
  let(:yp) { people(:yp_a_1) }

  def sub_nav_of(doc, href)
    doc.css("ul.nav-sub").find do |ul|
      ul.css("a").any? { |a| a["href"] == href }
    end
  end

  def booked_entry(amount_cents:)
    AccountingEntry.create!(subject: yp, author: admin, amount_cents: amount_cents,
      amount_currency: "EUR", description: "Teilnahmebeitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  # The heads of the four sections, in the order they stand.
  def section_heads(doc) = doc.css("#dereg-sections .dereg-section-head")

  def section_titles(doc) = section_heads(doc).map { |head| head.css("span").first.text.strip }

  def section_summary(doc, key)
    section_heads(doc)
      .find { |head| head["data-bs-target"] == "#dereg-section-#{key}" }
      .css(".dereg-section-summary").text.strip
  end

  def section_body(doc, key) = doc.css("#dereg-section-#{key}").first

  def open_sections(doc) = doc.css("#dereg-sections .collapse.show").pluck("id")

  # The compact row a document leads with, and the frame its preview opens.
  def document_row(doc, key) = section_body(doc, key).css(".dereg-doc-row").first

  def document_frame(doc, key)
    doc.css("#dereg-sections #dereg-section-#{key}_preview iframe.dereg-doc-frame").first
  end

  # The two lists of the summary head, left column first.
  def summary_lists(doc) = doc.css(".dereg-summary dl")

  def rows_of(list)
    list.css("dt").map { |dt| dt.text.strip }.zip(list.css("dd").to_a)
  end

  def summary_row(doc, label)
    rows_of(summary_lists(doc).last).find { |caption, _dd| caption == label }&.last
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
      expect(doc.css("#main form")).to be_empty
      expect(doc.css("#main textarea")).to be_empty
      expect(doc.css("#main input[type=checkbox]")).to be_empty
    end

    # The head says what the deregistration is on the left and what it comes to
    # on the right, and the sections below carry the detail.
    describe "the summary head" do
      it "leads with the kind and ends with where the registration stands" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(summary_lists(doc).size).to eq(2)
        left = rows_of(summary_lists(doc).first)
        expect(left.map(&:first))
          .to eq(["Art", "Abmeldung angefragt am", "Abmeldung zum", "Anmeldestatus"])
        expect(left.first.last.text.strip).to eq("Abmeldung (durch die Person)")
        expect(left.last.last.text.strip).to eq(yp.status_log_display)
        expect(left.last.last.text).to include("(#{yp.status})")
      end

      it "names a termination as one" do
        yp.update!(deregistration_kind: "termination")

        get :show, params: {person_id: yp.id}

        expect(rows_of(summary_lists(Nokogiri::HTML(response.body)).first).first.last.text.strip)
          .to eq("Kündigung (durch das Kontingent)")
      end

      # A ticket is the exception, so its row shows up only where there is one.
      it "shows the ticket row only where there is a ticket" do
        get :show, params: {person_id: yp.id}

        expect(rows_of(summary_lists(Nokogiri::HTML(response.body)).first).map(&:first))
          .not_to include("Ticket")

        yp.update!(deregistration_issue: "Ticket 1")
        get :show, params: {person_id: yp.id}

        left = rows_of(summary_lists(Nokogiri::HTML(response.body)).first)
        expect(left.map(&:first)).to eq(["Art", "Ticket", "Abmeldung angefragt am",
          "Abmeldung zum", "Anmeldestatus"])
        expect(left[1].last.text.strip).to eq("Ticket 1")
      end

      it "counts the amounts up to what is paid back" do
        booked_entry(amount_cents: 10_000)
        yp.update!(deregistration_actual_compensation_cents: 5_000)

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(rows_of(summary_lists(doc).last).map(&:first))
          .to eq(["Teilnahmebeitrag", "Bezahlt", "Einbehalt (Entschädigung)", "Rückzahlung"])
        refund = summary_row(doc, "Rückzahlung")
        expect(refund.css("span.fw-semibold").first.text.strip).to match(/\A50[^\d]*€\z/)
        expect(refund.text).to include("(bezahlt)", "(Einbehalt)", "−")
        expect(refund.text).not_to include("Bereits bezahl")
      end

      # The compensation is the larger amount, so nothing comes back and the
      # person still owes the difference.
      it "asks for a Forderung in red where the compensation outgrows what was paid" do
        booked_entry(amount_cents: 10_000)
        yp.update!(deregistration_actual_compensation_cents: 50_000)

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(rows_of(summary_lists(doc).last).map(&:first).last).to eq("Forderung")
        claim = summary_row(doc, "Forderung")
        amount = claim.css("span.fw-semibold").first
        expect(amount["style"]).to include("var(--bs-red)")
        expect(amount.text.strip).to match(/\A400[^\d]*€\z/)
        expect(claim.text).to include("(bezahlt)", "(Einbehalt)")
      end

      # Nothing was paid and nothing is held back, so the row is the refund of
      # nothing -- never a Forderung.
      it "calls it a Rückzahlung while both amounts are zero" do
        yp.update!(deregistration_actual_compensation_cents: 0)

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(rows_of(summary_lists(doc).last).map(&:first).last).to eq("Rückzahlung")
        expect(summary_row(doc, "Rückzahlung").css("span.fw-semibold").first.text.strip)
          .to match(/\A0[^\d]*€\z/)
      end

      # The fee names its own reduction where there is one, behind the amount.
      it "names the reduction behind the fee" do
        yp.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "rdp Delegate")

        get :show, params: {person_id: yp.id}

        fee = summary_row(Nokogiri::HTML(response.body), "Teilnahmebeitrag")
        expect(fee.css("span.muted").first.text.strip).to eq("(rdp Delegate: reduziert um 500€)")
      end

      it "leaves the fee alone where it is the regular one" do
        get :show, params: {person_id: yp.id}

        expect(summary_row(Nokogiri::HTML(response.body), "Teilnahmebeitrag").css("span.muted"))
          .to be_empty
      end
    end

    # Four sections, each opening on its own, and no headings of their own: the
    # head of a section is its heading and its trigger.
    describe "the sections" do
      it "carries the four heads in order, the first one open" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(section_titles(doc)).to eq(["Abmeldung erfassen", "Abmelde-Formular",
          "Kreditor für Rückzahlung", "Beleg für Rückzahlung in Moss"])
        expect(section_heads(doc).pluck("data-bs-target")).to eq(%w[
          #dereg-section-capture #dereg-section-form
          #dereg-section-creditor #dereg-section-receipt
        ])
        expect(section_heads(doc).pluck("aria-expanded")).to eq(%w[true false false false])
        expect(open_sections(doc)).to eq(["dereg-section-capture"])
        expect(doc.css("#main h3")).to be_empty
      end

      it "lets every section open on its own and says where to write the choice" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(doc.css("#dereg-sections .collapse").pluck("data-bs-parent").compact).to be_empty
        expect(doc.css("#dereg-sections").first["data-sections-url"])
          .to eq(sections_person_deregistration_path(yp))
      end

      it "opens the sections the login user last left open" do
        admin.wsjrdp_user_preferences["deregistration_open_sections"] = %w[creditor receipt]

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(open_sections(doc)).to eq(%w[dereg-section-creditor dereg-section-receipt])
        expect(section_heads(doc).pluck("aria-expanded")).to eq(%w[false false true true])
      end

      it "opens nothing where the login user closed everything" do
        admin.wsjrdp_user_preferences["deregistration_open_sections"] = []

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(open_sections(doc)).to be_empty
        expect(section_heads(doc).pluck("aria-expanded")).to eq(%w[false false false false])
      end

      # An older deploy's key, a hand-edited one: only what the page knows counts.
      it "keeps only the keys it knows from what is stored" do
        admin.wsjrdp_user_preferences["deregistration_open_sections"] = %w[nonsense form]

        get :show, params: {person_id: yp.id}

        expect(open_sections(Nokogiri::HTML(response.body))).to eq(["dereg-section-form"])
      end

      it "reads a stored value that is no list as nothing stored" do
        admin.wsjrdp_user_preferences["deregistration_open_sections"] = "creditor"

        get :show, params: {person_id: yp.id}

        expect(open_sections(Nokogiri::HTML(response.body))).to eq(["dereg-section-capture"])
      end
    end

    describe "#sections" do
      it "remembers the open sections in the page's order, for the login user" do
        post :sections, params: {person_id: yp.id, sections: "receipt,capture"}

        expect(response).to have_http_status(:no_content)
        expect(admin.reload.wsjrdp_user_preferences["deregistration_open_sections"])
          .to eq(%w[capture receipt])
        # The preference belongs to whoever is logged in, not to the person shown.
        expect(yp.reload.wsjrdp_user_preferences["deregistration_open_sections"]).to be_nil
      end

      it "remembers that everything is closed" do
        post :sections, params: {person_id: yp.id, sections: ""}

        expect(response).to have_http_status(:no_content)
        expect(admin.reload.wsjrdp_user_preferences["deregistration_open_sections"]).to eq([])
      end

      it "refuses a list with a section it does not know and remembers nothing" do
        post :sections, params: {person_id: yp.id, sections: "capture,nonsense"}

        expect(response).to have_http_status(422)
        expect(admin.reload.wsjrdp_user_preferences["deregistration_open_sections"]).to be_nil
      end

      it "refuses a request without a list" do
        post :sections, params: {person_id: yp.id}

        expect(response).to have_http_status(422)
      end

      # It writes, so it is a POST and only that.
      it "has no GET" do
        expect(post: sections_person_deregistration_path(yp)).to be_routable
        expect(get: sections_person_deregistration_path(yp)).not_to be_routable
      end
    end

    # What the finance team writes down, as it stands: the page shows it, the
    # Bearbeiten link in the section's bar changes it.
    describe "the Abmeldung erfassen section" do
      it "shows the values and no form" do
        get :show, params: {person_id: yp.id}

        body = section_body(Nokogiri::HTML(response.body), "capture")
        expect(body.css("form")).to be_empty
        expect(body.css("dt").map { |dt| dt.text.strip }).to eq([
          "Art", "Ticket Abmeldung", "Abmeldung angefragt am", "Abmeldung zum",
          "Entschädigung", "Entschädigung nach T&R",
          "Entschädigung nach T&R im Abmelde-Formular", "Text im Beleg",
          "Erklärungsabsatz im Beleg"
        ])
      end

      # Both flags mean "shown" while their key is absent.
      it "reads both flags as shown while nothing is stored" do
        get :show, params: {person_id: yp.id}

        rows = rows_of(section_body(Nokogiri::HTML(response.body), "capture"))
          .map { |label, dd| [label, dd.text.strip] }
        expect(rows).to include(
          ["Entschädigung nach T&R im Abmelde-Formular", "anzeigen"],
          ["Text im Beleg", "–"],
          ["Erklärungsabsatz im Beleg", "anzeigen"]
        )
      end

      it "reads a stored off as hidden, and shows the stored text" do
        yp.update!(deregistration_form_show_contractual_compensation: false,
          deregistration_refund_receipt_show_default_explanation: false,
          deregistration_refund_receipt_text: "Hallo Team")

        get :show, params: {person_id: yp.id}

        rows = rows_of(section_body(Nokogiri::HTML(response.body), "capture"))
          .map { |label, dd| [label, dd.text.strip] }
        expect(rows).to include(
          ["Entschädigung nach T&R im Abmelde-Formular", "ausblenden"],
          ["Text im Beleg", "Hallo Team"],
          ["Erklärungsabsatz im Beleg", "ausblenden"]
        )
      end

      # The refund belongs to the head, which counts the amounts up.
      it "leaves the refund to the head" do
        get :show, params: {person_id: yp.id}

        expect(section_body(Nokogiri::HTML(response.body), "capture")
          .css("dt").map { |dt| dt.text.strip }).not_to include("Rückzahlung")
      end
    end

    # The declaration the person signs: a button and, where there is no document
    # to offer, the reasons. It is offered for a withdrawal whose effective date
    # is known.
    describe "the Abmelde-Formular section" do
      before { yp.update!(deregistration_effective_date: Date.new(2026, 10, 31)) }

      it "answers with the pdf" do
        get :form, params: {person_id: yp.id}

        expect(response).to be_successful
        expect(response.media_type).to eq("application/pdf")
        expect(response.body).to start_with("%PDF")
        expect(response.headers["Content-Disposition"]).to start_with("inline")
        expect(response.headers["Content-Disposition"]).to include("Abmeldung")
      end

      it "offers the document with no form and no hint of its own" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        body = section_body(doc, "form")
        expect(body.css("form")).to be_empty
        expect(body.css("input[type=radio]")).to be_empty
        expect(body.css("#deregistration_form_hint")).to be_empty
        expect(section_summary(doc, "form")).to eq("")
      end

      it "greys the button out for a termination and says why" do
        yp.update!(deregistration_kind: "termination")

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        body = section_body(doc, "form")
        greyed = body.css("a#deregistration_form_submit.disabled").first
        expect(greyed).to be_present
        expect(greyed["href"]).to be_nil
        expect(greyed.parent["title"]).to include("Die Art ist Kündigung")
        hint = body.css("#deregistration_form_hint").first
        expect(hint.text).to include("Die Art ist Kündigung")
        expect(hint.text).not_to include("Abmeldung zum")
        expect(section_summary(doc, "form")).to eq("")
      end

      it "greys the button out while the effective date is unknown and says why" do
        yp.update!(deregistration_effective_date: nil)

        get :show, params: {person_id: yp.id}

        body = section_body(Nokogiri::HTML(response.body), "form")
        expect(body.css("a#deregistration_form_submit.disabled")).to be_present
        hint = body.css("#deregistration_form_hint").first
        expect(hint.text).to include("Bei „Abmeldung zum“ ist kein Datum eingetragen.")
        expect(hint.text).not_to include("Kündigung")
      end

      it "names both reasons where both apply" do
        yp.update!(deregistration_kind: "termination", deregistration_effective_date: nil)

        get :show, params: {person_id: yp.id}

        hint = Nokogiri::HTML(response.body).css("#deregistration_form_hint").first
        expect(hint.text).to include("Die Art ist Kündigung")
        expect(hint.text).to include("Bei „Abmeldung zum“ ist kein Datum eingetragen.")
      end

      # What the document says about the compensation of the T&R is stored on the
      # person, so the request carries nothing of it.
      it "builds the document from the person's flag alone" do
        yp.update!(deregistration_form_show_contractual_compensation: false)
        built = nil
        expect(Wsjrdp2027::DeregistrationForm).to receive(:new).with(yp)
          .and_wrap_original { |original, *args| built = original.call(*args) }

        get :form, params: {person_id: yp.id}

        expect(response.body).to start_with("%PDF")
        expect(built.show_contractual_compensation?).to be(false)
        expect(built.to_sys_inputs[:contractual_compensation_cents]).to eq("")
      end

      # The page offers no button then, so this is a URL typed in by hand.
      it "sends a request for a document it does not offer back to the page" do
        yp.update!(deregistration_kind: "termination")

        get :form, params: {person_id: yp.id}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:alert]).to include("Die Art ist Kündigung")
      end

      # Nothing is stored on the way, so the document is a GET and only that.
      it "has no POST" do
        expect(get: form_person_deregistration_path(yp)).to be_routable
        expect(post: form_person_deregistration_path(yp)).not_to be_routable
      end
    end

    # What the finance team types into Moss before the refund can be paid.
    describe "the Kreditor section" do
      it "shows the creditor's master data" do
        get :show, params: {person_id: yp.id}

        body = section_body(Nokogiri::HTML(response.body), "creditor")
        expect(body.css("dt").map { |dt| dt.text.strip })
          .to include("Name", "Standard-Sachkonto", "Standard Kostenstelle",
            "Standard Sphäre", "Standard-Team", "Land der Empfängerbank", "IBAN",
            "Name des Kontoinhabers", "Standard-Zahlungsmethode", "Land",
            "Straße und Hausnummer", "Postleitzahl", "Ort")
        expect(body.css("dd").map { |dd| dd.text.strip })
          .to include("TN #{yp.id}", "41030 Teilnehmendenbeiträge", "Banküberweisung")
      end

      # In a line of its own above the values, not in the section head.
      it "links to where those creditors are kept in Moss" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        body = section_body(doc, "creditor")
        link = body.css("a").find { |a| a["href"] == "https://getmoss.com/app/accounting/suppliers" }
        expect(link).to be_present
        expect(link["target"]).to eq("_blank")
        expect(link.text).to include("Kreditoren in Moss")
        expect(link.parent.xpath("following-sibling::*[1]").first.name).to eq("dl")
        expect(section_heads(doc).first.css("a")).to be_empty
      end

      # The closed section names who is paid, where, and on which account.
      # The name is what is typed into Moss, so it is what the bar carries --
      # and nothing else.
      it "names the creditor in the head" do
        yp.update!(sepa_iban: "DE02120300000000202051")

        get :show, params: {person_id: yp.id}

        expect(section_summary(Nokogiri::HTML(response.body), "creditor")).to eq("TN #{yp.id}")
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

      # A German IBAN needs no BIC, and most of these carry none -- so the row is
      # there only where there is something to show.
      it "shows the BIC row only where a BIC is stored" do
        get :show, params: {person_id: yp.id}
        expect(section_body(Nokogiri::HTML(response.body), "creditor")
          .css("dt").map { |dt| dt.text.strip }).not_to include("BIC")

        yp.update!(sepa_bic: "genode61abc")
        get :show, params: {person_id: yp.id}

        body = section_body(Nokogiri::HTML(response.body), "creditor")
        expect(body.css("dt").map { |dt| dt.text.strip }).to include("BIC")
        expect(body.css("dd").map { |dd| dd.text.strip }).to include("GENODE61ABC")
      end
    end

    # The slip the refund is paid from: what it will say, and the button that
    # hands it over.
    describe "the Beleg section" do
      it "previews what the receipt will say, with no form of its own" do
        groups(:unit_a).update!(additional_info: {"group_code" => "A1"})

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        body = section_body(doc, "receipt")
        expect(body.css("dt").map { |dt| dt.text.strip })
          .to include("Team/Unit", "Rolle", "Beitrag", "Bisher bezahlt",
            "Buchungstext", "Verwendungszweck", "Kontoinhaber", "IBAN")
        expect(body.text).to include("A1", "Youth Participant in einer Unit")
        expect(body.css("textarea")).to be_empty
        expect(body.css("input[type=checkbox]")).to be_empty
        expect(body.css("form")).to be_empty
        # The document itself comes below the list it is summed up in.
        expect(body.css("dl").first.xpath("following-sibling::*[1]").first["class"])
          .to eq("dereg-doc-row")
      end

      it "carries nothing in the head" do
        get :show, params: {person_id: yp.id}

        expect(section_summary(Nokogiri::HTML(response.body), "receipt")).to eq("")
      end

      it "answers with the pdf, inline" do
        get :refund_receipt, params: {person_id: yp.id}

        expect(response).to be_successful
        expect(response.media_type).to eq("application/pdf")
        expect(response.body).to start_with("%PDF")
        expect(response.headers["Content-Disposition"]).to start_with("inline")
        expect(response.headers["Content-Disposition"]).to include("R%C3%BCckzahlung.pdf")
      end

      # It stores nothing, so it is a GET and only that.
      it "has no POST" do
        expect(get: refund_receipt_person_deregistration_path(yp)).to be_routable
        expect(post: refund_receipt_person_deregistration_path(yp)).not_to be_routable
      end
    end

    # Both documents lead with the same compact row -- a picture of page 1, the
    # name it is saved under, what it will say, and the three ways to it -- above
    # a preview frame that is a collapsible of the page like the sections are.
    describe "the document previews" do
      before { yp.update!(deregistration_effective_date: Date.new(2026, 10, 31)) }

      [["form", :form], ["receipt", :refund_receipt]].each do |key, action|
        describe "the #{key} document" do
          let(:document_path) { public_send(:"#{action}_person_deregistration_path", yp) }
          let(:thumbnail_path) do
            public_send(:"#{action}_person_deregistration_path", yp, format: :png)
          end

          it "leads with the picture, the facts and the three buttons" do
            get :show, params: {person_id: yp.id}

            row = document_row(Nokogiri::HTML(response.body), key)
            # The section is closed, so the picture carries its address alone.
            thumb = row.css("img.dereg-doc-thumb").first
            expect(thumb["data-src"]).to eq(thumbnail_path)
            expect(thumb["src"]).to be_nil
            expect(thumb["loading"]).to eq("lazy")
            expect(thumb["alt"]).to eq(row.css(".fw-semibold").first.text.strip)
            expect(row.css(".muted").first.text).to include(" · ")

            # In one row, in this order: the preview, the new tab, the file.
            actions = row.css(".dereg-doc-actions > *")
            expect(actions.map(&:name)).to eq(%w[button a a])
            expect(actions.map { |action| action.text.strip }).to eq(["Vorschau", "In neuem Tab öffnen", "PDF speichern"])
            expect(actions.pluck("class")).to all(include("btn btn-sm"))
            expect(row.css("a").pluck("href")).to eq([document_path, "#{document_path}?download=1"])
            expect(row.css("a").first["target"]).to eq("_blank")
            expect(row.css(".btn-group")).to be_empty
          end

          # The toggle keeps one label whatever the preview does, so the two
          # buttons beside it never move.
          it "toggles the preview frame from the row" do
            get :show, params: {person_id: yp.id}

            toggle = document_row(Nokogiri::HTML(response.body), key)
              .css("button.dereg-doc-toggle").first
            expect(toggle["data-bs-toggle"]).to eq("collapse")
            expect(toggle["data-bs-target"]).to eq("#dereg-section-#{key}_preview")
            expect(toggle["aria-expanded"]).to eq("false")
            expect(toggle.text.strip).to eq("Vorschau")
            expect(toggle.css("i.fa-chevron-down")).to be_present
          end

          # A closed frame carries the address alone, so a preview nobody opened
          # costs no document.
          it "keeps the closed frame empty" do
            get :show, params: {person_id: yp.id}

            doc = Nokogiri::HTML(response.body)
            frame = document_frame(doc, key)
            expect(frame).to be_present
            expect(frame["data-src"]).to eq(document_path)
            expect(frame["src"]).to be_nil
            expect(frame["title"]).to be_present
            expect(open_sections(doc)).not_to include("dereg-section-#{key}_preview")
          end

          # A picture costs a document, so it is asked for only in a section
          # that stands open -- at once where the login user left it open.
          it "fills the picture in a section the login user left open" do
            admin.wsjrdp_user_preferences["deregistration_open_sections"] = [key]

            get :show, params: {person_id: yp.id}

            thumb = document_row(Nokogiri::HTML(response.body), key).css("img.dereg-doc-thumb").first
            expect(thumb["src"]).to eq(thumbnail_path)
            expect(thumb["data-src"]).to eq(thumbnail_path)
          end

          it "fills the frame the login user left open in an open section" do
            admin.wsjrdp_user_preferences["deregistration_open_sections"] = [key, "#{key}_preview"]

            get :show, params: {person_id: yp.id}

            doc = Nokogiri::HTML(response.body)
            expect(document_frame(doc, key)["src"]).to eq(document_path)
            expect(open_sections(doc)).to eq(["dereg-section-#{key}", "dereg-section-#{key}_preview"])
            expect(document_row(doc, key).css("button.dereg-doc-toggle").first["aria-expanded"])
              .to eq("true")
          end

          # An open preview inside a closed section is not on view, so its
          # document is not asked for until the section opens.
          it "keeps the frame empty while the section around it is closed" do
            admin.wsjrdp_user_preferences["deregistration_open_sections"] = ["#{key}_preview"]

            get :show, params: {person_id: yp.id}

            doc = Nokogiri::HTML(response.body)
            expect(document_frame(doc, key)["src"]).to be_nil
            expect(document_frame(doc, key)["data-src"]).to eq(document_path)
            expect(open_sections(doc)).to eq(["dereg-section-#{key}_preview"])
          end

          it "answers page 1 as a picture that nothing may keep" do
            get action, params: {person_id: yp.id}, format: :png

            expect(response).to be_successful
            expect(response.media_type).to eq("image/png")
            expect(response.body.b).to start_with(Wsjrdp2027::TypstDocument::PNG_SIGNATURE)
            expect(response.headers["Cache-Control"]).to include("private", "no-store")
          end

          it "hands the pdf over as a file to save" do
            get action, params: {person_id: yp.id, download: "1"}

            expect(response.media_type).to eq("application/pdf")
            expect(response.headers["Content-Disposition"]).to start_with("attachment")
            expect(response.body).to start_with("%PDF")
          end
        end
      end

      # The greyed-out button stands in the document's place, so there is nothing
      # to preview.
      it "shows neither row nor frame while the form is unavailable" do
        yp.update!(deregistration_effective_date: nil)

        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(document_row(doc, "form")).to be_nil
        expect(doc.css("#dereg-section-form_preview")).to be_empty
        expect(section_body(doc, "form").css("#deregistration_form_hint")).to be_present
        # The receipt is offered whatever the form says.
        expect(document_row(doc, "receipt")).to be_present
      end

      it "remembers an open preview like a section" do
        post :sections, params: {person_id: yp.id, sections: "capture,form_preview"}

        expect(response).to have_http_status(:no_content)
        expect(admin.reload.wsjrdp_user_preferences["deregistration_open_sections"])
          .to eq(%w[capture form_preview])
      end
    end

    # The way into the form sits beside the head of the section it changes, as
    # a link rather than a second button -- and nowhere in the toolbar, which
    # is far from that section.
    it "offers Bearbeiten in the bar of Abmeldung erfassen and not in the toolbar" do
      get :show, params: {person_id: yp.id}

      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".btn-toolbar a").pluck("href")).not_to include(edit_person_deregistration_path(yp))

      bar = doc.css("#dereg-sections .dereg-section-bar").first
      link = bar.css("a.dereg-section-action").first
      expect(link).to be_present
      expect(link["href"]).to eq(edit_person_deregistration_path(yp))
      expect(link.text).to include("Bearbeiten")
      expect(bar.css("button.dereg-section-head a")).to be_empty
      expect(doc.css("#dereg-sections a.dereg-section-action").size).to eq(1)
    end

    # Abmeldung erfassen is edited where it stands: its body is a turbo frame,
    # the Bearbeiten link loads the form into that frame, and a save replaces the
    # head by its id. The other three sections carry no frame of their own.
    describe "the capture frame" do
      it "wraps the capture body and no other" do
        get :show, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        expect(section_body(doc, "capture").css("turbo-frame#deregistration_capture"))
          .to be_present
        %w[form creditor receipt].each do |key|
          expect(section_body(doc, key).css("turbo-frame")).to be_empty,
            "the #{key} section carries a turbo frame"
        end
      end

      # The section opens as the frame's content arrives (turbo:frame-load in
      # the page script), so the link carries nothing but its frame.
      it "sends the Bearbeiten link into the frame" do
        get :show, params: {person_id: yp.id}

        link = Nokogiri::HTML(response.body)
          .css("#dereg-sections a.dereg-section-action").first
        expect(link["data-turbo-frame"]).to eq("deregistration_capture")
        expect(link.attributes.keys.grep(/^data-/)).to eq(["data-turbo-frame"])
      end

      it "gives the summary head an id to be replaced by" do
        get :show, params: {person_id: yp.id}

        expect(Nokogiri::HTML(response.body).css(".dereg-summary#dereg-summary")).to be_present
      end
    end

    # The javascript that writes the open section reads the token out of the
    # page's meta tag, so the page has to carry one.
    context "with forgery protection on" do
      around do |example|
        was = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
        ActionController::Base.allow_forgery_protection = was
      end

      it "carries the csrf token the section request needs" do
        get :show, params: {person_id: yp.id}

        token = Nokogiri::HTML(response.body).css("meta[name=csrf-token]").first
        expect(token["content"]).to be_present
      end
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

    describe "the form" do
      it "renders it on edit, cancelling back to the page" do
        get :edit, params: {person_id: yp.id}

        expect(response).to be_successful
        doc = Nokogiri::HTML(response.body)
        expect(doc.css("form input[name='person[deregistration_issue]']")).to be_present
        expect(doc.css("a").pluck("href")).to include(person_deregistration_path(yp))
      end

      # The page asks for the form as a frame, a deep link for the whole page:
      # both answers carry the same frame, so both lead to the same form.
      it "answers a frame request with the frame and the form in it" do
        request.headers["Turbo-Frame"] = "deregistration_capture"

        get :edit, params: {person_id: yp.id}

        expect(response).to be_successful
        frame = Nokogiri::HTML(response.body).css("turbo-frame#deregistration_capture").first
        expect(frame).to be_present
        expect(frame.css("input[name='person[deregistration_issue]']")).to be_present
      end

      it "carries the same frame on a plain request" do
        get :edit, params: {person_id: yp.id}

        frame = Nokogiri::HTML(response.body).css("turbo-frame#deregistration_capture").first
        expect(frame).to be_present
        expect(frame.css("form")).to be_present
      end

      # Two ways out of the form and one beside them, in one row and in this
      # order.
      it "offers Speichern, Speichern und weiter bearbeiten and Abbrechen" do
        get :edit, params: {person_id: yp.id}

        actions = Nokogiri::HTML(response.body).css(".dereg-form-actions > *")
        expect(actions.map(&:name)).to eq(%w[button button a])
        expect(actions.map { |action| action.text.strip })
          .to eq(["Speichern", "Speichern und weiter bearbeiten", "Abbrechen"])
        expect(actions[1]["name"]).to eq("stay")
        expect(actions[1]["value"]).to eq("1")
        expect(actions[2]["href"]).to eq(person_deregistration_path(yp))
      end

      it "offers both kinds, the withdrawal preselected" do
        get :edit, params: {person_id: yp.id}

        select = Nokogiri::HTML(response.body)
          .css("select[name='person[deregistration_kind]']").first
        expect(select).to be_present
        expect(select.css("option").pluck("value")).to eq(%w[withdrawal termination])
        expect(select.css("option[selected]").pluck("value")).to eq(["withdrawal"])
      end

      # Everything the two documents carry is edited here: the text and the two
      # flags, both checked while their key is absent.
      it "carries the receipt text and the two flags" do
        get :edit, params: {person_id: yp.id}

        doc = Nokogiri::HTML(response.body)
        field = doc.css("textarea[name='person[deregistration_refund_receipt_text]']").first
        expect(field).to be_present
        expect(field["rows"]).to eq("3")
        expect(field["placeholder"]).to eq("Optionaler Text vor dem Erklärungsabsatz")

        %w[
          deregistration_form_show_contractual_compensation
          deregistration_refund_receipt_show_default_explanation
        ].each do |attr|
          box = doc.css("input[type=checkbox][name='person[#{attr}]']").first
          expect(box).to be_present, "no checkbox for #{attr}"
          expect(box["checked"]).to be_present
          expect(doc.css("input[type=hidden][name='person[#{attr}]']")).to be_present
        end
      end

      it "unchecks a flag that was switched off" do
        yp.update!(deregistration_refund_receipt_show_default_explanation: false)

        get :edit, params: {person_id: yp.id}

        box = Nokogiri::HTML(response.body).css(
          "input[type=checkbox][name='person[deregistration_refund_receipt_show_default_explanation]']"
        ).first
        expect(box["checked"]).to be_nil
      end

      it "shows a stored text in the field" do
        yp.update!(deregistration_refund_receipt_text: "Hallo Team")

        get :edit, params: {person_id: yp.id}

        field = Nokogiri::HTML(response.body)
          .css("textarea[name='person[deregistration_refund_receipt_text]']").first
        expect(field.text.strip).to eq("Hallo Team")
      end

      it "saves the changes and redirects to the page" do
        put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(yp.reload.deregistration_issue).to eq("Ticket 1")
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

      # An unchecked box arrives as "0" (the hidden companion), and that is the
      # one value stored: a false, not the string.
      # The form sends the kind and both flags on every save; where they are
      # the defaults, nothing is written and nothing is announced.
      it "says nothing changed when the form sends the defaults again" do
        put :update, params: {person_id: yp.id,
                              person: {deregistration_kind: "withdrawal",
                                       deregistration_form_show_contractual_compensation: "1",
                                       deregistration_refund_receipt_text: "",
                                       deregistration_refund_receipt_show_default_explanation: "1"}}

        expect(response).to redirect_to(person_deregistration_path(yp))
        expect(flash[:notice]).to eq("Angaben zur Abmeldung wurden nicht verändert")
        expect(yp.reload.additional_info).not_to have_key("deregistration_record")
      end

      # A default that an older save stored reads like its absence, so shedding
      # it is no change either.
      it "says nothing changed when a stored default is shed" do
        yp.update!(additional_info: yp.additional_info.merge("deregistration_record" => {"kind" => "withdrawal"}))

        put :update, params: {person_id: yp.id, person: {deregistration_kind: "withdrawal"}}

        expect(flash[:notice]).to eq("Angaben zur Abmeldung wurden nicht verändert")
        expect(yp.reload.additional_info).not_to have_key("deregistration_record")
      end

      it "stores an explicit off for both flags and names them in the flash" do
        put :update, params: {person_id: yp.id,
                              person: {deregistration_refund_receipt_text: "Hallo Team",
                                       deregistration_form_show_contractual_compensation: "0",
                                       deregistration_refund_receipt_show_default_explanation: "0"}}

        record = yp.reload.additional_info["deregistration_record"]
        expect(record["form_show_contractual_compensation"]).to be(false)
        expect(record["refund_receipt_show_default_explanation"]).to be(false)
        expect(yp.deregistration_refund_receipt_text).to eq("Hallo Team")
        expect(flash[:notice]).to include(
          "Entschädigung nach T&R im Abmelde-Formular: anzeigen → ausblenden",
          "Erklärungsabsatz im Beleg: anzeigen → ausblenden",
          "Text im Beleg: – → Hallo Team"
        )
      end

      # Shown is the default, and the default is no value at all -- so with both
      # flags back to it the whole sub-object is gone.
      it "removes both flags where the boxes are checked" do
        yp.update!(deregistration_form_show_contractual_compensation: false,
          deregistration_refund_receipt_show_default_explanation: false)

        put :update, params: {person_id: yp.id,
                              person: {deregistration_form_show_contractual_compensation: "1",
                                       deregistration_refund_receipt_show_default_explanation: "1"}}

        expect(yp.reload.additional_info).not_to have_key("deregistration_record")
        expect(flash[:notice]).to include(
          "Entschädigung nach T&R im Abmelde-Formular: ausblenden → anzeigen",
          "Erklärungsabsatz im Beleg: ausblenden → anzeigen"
        )
      end

      # An emptied field is no text at all, and the receipt's default greeting
      # comes back.
      it "drops the text key when the field is emptied" do
        yp.update!(deregistration_refund_receipt_text: "Hallo Team")

        put :update, params: {person_id: yp.id,
                              person: {deregistration_refund_receipt_text: ""}}

        expect(yp.reload.additional_info).not_to have_key("deregistration_record")
        expect(flash[:notice]).to include("Text im Beleg: Hallo Team → –")
      end

      it "leaves a flag alone where the form sends none" do
        yp.update!(deregistration_refund_receipt_show_default_explanation: false)

        put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}}

        expect(yp.reload.additional_info["deregistration_record"])
          .to eq("refund_receipt_show_default_explanation" => false)
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

      it "honours the return_url the form carries" do
        put :update, params: {person_id: yp.id, return_url: person_fee_path(yp),
                              person: {deregistration_issue: "Ticket 3"}}

        expect(response).to redirect_to(person_fee_path(yp))
        expect(yp.reload.deregistration_issue).to eq("Ticket 3")
      end

      # Without Turbo the save leaves the form behind, unless it is to go on.
      it "leads back to the form where the save is to go on" do
        put :update, params: {person_id: yp.id, stay: "1",
                              person: {deregistration_issue: "Ticket 4"}}

        expect(response).to redirect_to(edit_person_deregistration_path(yp))
        expect(yp.reload.deregistration_issue).to eq("Ticket 4")
      end
    end

    # The form sits in the capture frame, so Turbo submits it as a turbo_stream:
    # the save answers the three places it touches -- the head, the frame and the
    # flash slot of the layout -- and never leaves the page.
    describe "a save from the frame" do
      def streams = Nokogiri::HTML(response.body).css("turbo-stream")

      def stream_actions = streams.map { |stream| [stream["action"], stream["target"]] }

      def stream(action, target)
        streams.find { |s| s["action"] == action && s["target"] == target }
      end

      it "answers the head, the read-only list and the flash" do
        put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}},
          format: :turbo_stream

        expect(response).to be_successful
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(stream_actions).to eq([["replace", "dereg-summary"],
          ["update", "deregistration_capture"], ["update", "flash"]])
        expect(yp.reload.deregistration_issue).to eq("Ticket 1")

        capture = stream("update", "deregistration_capture")
        expect(capture.css("dl")).to be_present
        expect(capture.css("form")).to be_empty
        expect(capture.text).to include("Ticket 1")
        expect(stream("update", "flash").text).to include("Ticket Abmeldung: – → Ticket 1")
      end

      # Speichern und weiter bearbeiten hands the form back, with what was saved
      # in its fields.
      it "hands the form back where the save is to go on" do
        put :update, params: {person_id: yp.id, stay: "1",
                              person: {deregistration_issue: "Ticket 1"}},
          format: :turbo_stream

        expect(stream_actions).to eq([["replace", "dereg-summary"],
          ["update", "deregistration_capture"], ["update", "flash"]])
        capture = stream("update", "deregistration_capture")
        expect(capture.css("form")).to be_present
        expect(capture.css("input[name='person[deregistration_issue]']").first["value"])
          .to eq("Ticket 1")
        expect(stream("update", "flash").text).to include("Ticket Abmeldung: – → Ticket 1")
      end

      # Nothing was stored, so there is no head to replace and nothing to
      # announce: the form comes back alone, with what the model said.
      it "brings the form back with its errors and nothing else" do
        put :update, params: {person_id: yp.id, person: {deregistration_kind: "foo"}},
          format: :turbo_stream

        expect(response).to have_http_status(422)
        expect(stream_actions).to eq([["update", "deregistration_capture"]])
        capture = stream("update", "deregistration_capture")
        expect(capture.css("form")).to be_present
        expect(capture.css("#error_explanation")).to be_present
        expect(yp.reload.deregistration_kind).to be_nil
      end

      it "says in the flash that nothing changed" do
        yp.update!(deregistration_issue: "Ticket 1")

        put :update, params: {person_id: yp.id, person: {deregistration_issue: "Ticket 1"}},
          format: :turbo_stream

        expect(stream("update", "flash").text)
          .to include("Angaben zur Abmeldung wurden nicht verändert")
        expect(stream("update", "deregistration_capture").css("form")).to be_empty
      end
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

    # A frame asking for the form is refused like the page it would sit in.
    it "refuses the form in the frame" do
      request.headers["Turbo-Frame"] = "deregistration_capture"

      expect { get :edit, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the deregistration form" do
      expect { get :form, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the receipt" do
      expect { get :refund_receipt, params: {person_id: yp.id} }
        .to raise_error(CanCan::AccessDenied)
    end

    it "refuses to remember a section" do
      expect { post :sections, params: {person_id: yp.id, sections: "capture"} }
        .to raise_error(CanCan::AccessDenied)
    end
  end
end
