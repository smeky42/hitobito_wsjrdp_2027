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
        + " werden"
        text "3. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden"
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule
        pdf.move_down 3.mm

        text "SEPA-Mandat", size: 12

        text "Die Teilnahmebeitrag zum Jamboree werden mittels SEPA-Basislastschrift eingezogen:"

        pdf.move_down 3.mm
        text "Ich ermächtige den Ring deutscher Pfadfinder*innenverbände e.V., die Zahlungen gemäß Zahlungsplan von meinem Konto mittels Lastschrift einzuziehen. Maßgeblich ist das von mir gewählte Zahlungsmodell (#{payment_role(@person).start_with?("EarlyPayer") ? "Einmalzahlung" : "Ratenzahlungen"}). Zugleich weise ich mein Kreditinstitut an, die vom Ring deutscher Pfadfinder*innenverbände e.V. auf mein Konto gezogenen Lastschriften einzulösen."

        pdf.move_down 3.mm
        text "Hinweis: Ich kann innerhalb von acht Wochen, beginnend mit dem Belastungsdatum, die Erstattung des belasteten Betrages verlangen."
        text "Es gelten dabei die mit meinem Kreditinstitut vereinbarten Bedingungen."

        pdf.move_down 3.mm
        attendee_data = pdf.make_table([
          [{content: "IBAN:", width: 150}, @person.sepa_iban],
          ["Mandatsreferenz:", "wsjrdp2027" + @person.id.to_s],
          ["Gläubiger-Identifikationsnummer:",
            "DE81 WSJ 0000 2017 275"], # Todo
          ["Kontoinhaber*in:", @person.sepa_name],
          ["Adresse:", @person.sepa_address]
        ],
          cell_style: {padding: 1, border_width: 0,
                       inline_format: true})
        attendee_data.draw

        pdf.move_down 3.mm

        if payment_role(@person).start_with?("EarlyPayer")
          text "Der Einzug des Gesamtbetrages von #{payment_value(@person)} € erfolgt am 5. August 2025."
        else
          text "Der Einzug erfolgt am 5. des jeweiligen Monats bzw. am darauffolgenden Werktag nach folgendem Ratenplan:"
          pdf.make_table(payment_array_table(@person), cell_style: {padding: 1,
                                                                    border_width: 0,
                                                                    inline_format: true,
                                                                    size: 8}).draw
        end

        pdf.move_down 3.mm
        text "Die Anzahlung wird frühestens nach dem Hochladen aller Anmeldeunterlagen eingezogen. Wir werden mindestens 7 Tage vor dem Einzug der Anzahlung über diesen informieren"
        text "Im Falle einer Rücklastschrift behalten wir uns vor, die dadurch entstehenden Kosten an die*den Teilnehmer*in weiterzugeben."

        pdf.move_down 3.mm
        pdf.make_table([
          [{content: @person.town + " den " + Time.zone.today.strftime("%d.%m.%Y"),
            height: 30}],
          ["______________________________", ""],
          [{content: @person.sepa_name, height: 30}, ""]
        ],
          cell_style: {width: 240, padding: 1, border_width: 0,
                       inline_format: true}).draw

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
