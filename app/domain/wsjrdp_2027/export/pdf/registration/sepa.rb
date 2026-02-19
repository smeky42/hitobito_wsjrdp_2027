# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Sepa < Section
      include ContractHelper

      self.name = "SEPA-Mandat"

      # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
      def render
        pdf.y = bounds.height - 60
        bounding_box([0, 230.mm], width: bounds.width, height: bounds.height - 210) do
          font_size(8) do
            text list, style: :italic, width: bounds.width
          end
        end
      end

      def list
        text "Was muss ich mit dem SEPA-Mandat machen?", size: 12
        text "Das SEPA-Mandat muss"
        text "1. vollständig unterschrieben werden"
        text '2. auf anmeldung.worldscoutjamboree.de unter "Upload>SEPA hochladen" hochgeladen' \
             " werden"
        text "3. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden"
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule
        pdf.move_down 3.mm

        text "SEPA-Mandat", size: 12

        pdf.move_down 1.mm
        text "Der Teilnahmebeitrag zum Jamboree"
        pdf.indent(0.75.cm) do
          pdf.make_table([
            [{content: "von", width: 3.cm}, @person.full_name],
            ["als", person_payment_role_full_name(@person)],
            ["in Höhe von", format_cents_de(@person.total_fee_cents)]
          ], cell_style: {padding: [1, 0, 1, 0], border_width: 0, inline_format: true}).draw
        end
        pdf.move_down 2
        text "wird mittels SEPA-Basislastschrift eingezogen:"

        pdf.move_down 4.mm
        text "Ich ermächtige den Ring deutscher Pfadfinder*innenverbände e.V., " \
             "die Zahlungen gemäß Zahlungsplan von meinem Konto mittels Lastschrift einzuziehen. " \
             "Maßgeblich ist das von mir gewählte Zahlungsmodell " \
             "(#{early_payer?(@person) ? "Einmalzahlung" : "Ratenzahlungen"}). " \
             "Zugleich weise ich mein Kreditinstitut an, die vom Ring deutscher " \
             "Pfadfinder*innenverbände e.V. auf mein Konto gezogenen Lastschriften einzulösen."

        pdf.move_down 2.mm
        text "Hinweis: Ich kann innerhalb von acht Wochen, beginnend mit dem " \
             "Belastungsdatum, die Erstattung des belasteten Betrages verlangen."
        pdf.move_down 1.mm
        text "Es gelten dabei die mit meinem Kreditinstitut vereinbarten Bedingungen."

        pdf.move_down 4.mm
        pdf.indent(0.75.cm) do
          pdf.make_table([
            [{content: "IBAN:", width: 5.5.cm}, @person.sepa_iban.upcase],
            ["Mandatsreferenz:", @person.sepa_mandate_id],
            ["Gläubiger-Identifikationsnummer:",
              "DE81 WSJ 0000 2017 275"],
            ["Kontoinhaber*in:", @person.sepa_name],
            ["Adresse:", @person.sepa_address]
          ], cell_style: {padding: [1, 0, 1, 0], border_width: 0, inline_format: true}).draw
        end
        pdf.move_down 3.mm

        if early_payer?(@person)
          text "Der Einzug des Gesamtbetrages von #{format_cents_de(@person.total_fee_cents)} erfolgt am 5. Januar 2026."
        else
          text "Der Einzug erfolgt am 5. des jeweiligen Monats bzw. am " \
               "darauffolgenden Banktag nach folgendem Ratenplan:"

          @person.installments_cents.each_slice(10).each do |installments_slice|
            pdf.move_down 1.mm
            dates = installments_slice.map(&:first).map do |year, month|
              I18n.with_locale(:de) do
                {
                  content: I18n.l(Time.zone.local(year, month, 5), format: "%b") + " #{year}",
                  width: 1.6.cm
                }
              end
            end
            euros = installments_slice.map { |a| format_cents_de(a[1], zero_cents: "") }
            pdf.make_table(
              [dates, euros],
              cell_style: {
                padding: 1.4,
                border_width: 0.5,
                border_color: "CCCCCC",
                align: :center,
                inline_format: true,
                size: 8
              }
            ).draw
          end
        end

        pdf.move_down 3.mm
        text "Der erste Einzug erfolgt frühestens nach dem Hochladen aller Anmeldeunterlagen. " \
             "Wir werden mindestens 4 Tage vor dem Einzug über diesen informieren"
        text "Im Falle einer Rücklastschrift behalten wir uns vor, " \
             "die dadurch entstehenden Kosten an die*den Teilnehmer*in weiterzugeben."

        pdf.move_down 3.mm
        pdf.make_table([
          [{content: @person.town + ", den " + Time.zone.today.strftime("%d.%m.%Y"),
            height: 30}],
          ["______________________________", ""],
          [{content: @person.sepa_name, height: 30}, ""]
        ],
          cell_style: {width: 240, padding: [1, 0, 1, 0], border_width: 0,
                       inline_format: true}).draw

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
