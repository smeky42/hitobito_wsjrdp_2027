# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Contract < Section
      include ContractHelper

      self.name = "Anmeldung"

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
        of_legal_age = @person.years.to_i >= 18

        text "Was muss ich mit der Anmeldung machen?", size: 12
        text "Die Anmeldung muss"
        text "1. vollständig unterschrieben werden"
        text '2. auf anmeldung.worldscoutjamboree.de unter "Upload>Anmeldung hochladen" hochgeladen werden'
        text "3. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden "
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        text "Anmeldung", size: 12

        text "von #{@person.full_name} geboren am #{@person.birthday.strftime("%d.%m.%Y")}, wohnhaft in #{@person.address}, #{@person.zip_code}, #{@person.town}"
        text "beim Ring deutscher Pfadfinder*innenverbände e.V (rdp) Chausseestraße 128/129, 10115 Berlin für das deutsche Kontingent zum 26. World Scout Jamboree 2027 in Polen."

        pdf.move_down 3.mm
        text "Die Teilnahme, als #{person_payment_role_full_name(@person)}, im deutschen Kontingent kostet #{get_full_regular_fee_eur(@person)} € und beinhaltet #{role_type(@person).starts_with?("Group::Unit") ? "die Vor- und Nachbereitung in Deutschland, die Reise nach Polen, eine Vor- oder Nachtour " : "die Vor- und Nachbereitung in Deutschland "} und die Teilnahme am 26. World Scout Jamboree in Polen."

        pdf.move_down 3.mm
        text "Die Reise ist für den Zeitraum vom 20.07 bis 18.08.2027 geplant. Der Reisezeitraum variiert je nach gewähltem Paket und Lage der Sommerferien. Reisedauer sind #{role_type(@person).starts_with?("Group::Unit") ? "17 bis 21" : "15 bis 17"} Tage."

        pdf.move_down 3.mm
        text "Hiermit #{of_legal_age ? "melde ich mich" : "melden wir unser Kind"}, #{@person.full_name} geboren am #{@person.birthday.strftime("%d.%m.%Y")}, verbindlich mit dem Paket für #{person_payment_role_full_name(@person)} zur Teilnahme im Deutschen Kontingent zum 26. World Scout Jamboree 2027 an. Mit der Anmeldung #{of_legal_age ? "akzeptiere ich" : "akzeptieren wir"} die Reisebedingungen, die vom rdp als Veranstalter vorgegeben werden."

        pdf.move_down 3.mm
        text "Der rdp behält sich das Recht vor, angekündigte Programminhalte durch andere zu ersetzen und notwendige Änderungen des Programms, unter Wahrung des Gesamtcharakters der Veranstaltung vorzunehmen."

        pdf.move_down 3.mm
        text "Es besteht die Möglichkeit, dass der Veranstalter des Jamborees in Polen ergänzende Bedingungen für die Teilnahme stellt und/oder weitere Daten abfragt. Der rdp muss diese ergänzenden Bedingungen an alle Teilnehmer*innen weitergeben, obwohl er auf den Inhalt keinen Einfluss hat, weil sonst eine Teilnahme nicht möglich ist. Die Teilnehmer*innen werden über diese Änderungen in Textform unterrichtet. Sollte der*die Teilnehmer*in mit diesen ergänzenden Bedingungen nicht einverstanden sein, kann er*sie nach Maßgabe von Punkt 8. der Reisebedingungen zu diesem Vertrag zurücktreten."

        if !of_legal_age
          pdf.move_down 3.mm
          text "Für die Dauer der Reise übertragen wir die Ausübung der Aufsichtspflicht und das Aufenthaltsbestimmungsrecht über unser Kind dem Reiseveranstalter. Wir sind damit einverstanden, dass die Ausübung im erforderlichen Ausmaß auf volljährige Betreuer*innen übertragen wird."
        end

        pdf.move_down 3.mm
        text "Als Bestandteil dieser Anmeldung haben wir folgende Dokumente in der Anlage zur Kenntnis genommen:"
        text "- die Teilnahme- und Reisebedingungen des rdp (v1 vom 28.06.2025)"
        text "- die Datenschutzhinweise (v1 vom 28.06.2025)"
        text ""
        text "Die Dokumente stehen auch unter www.worldscoutjamboree.de/downloads zur Verfügung."

        pdf.move_down 3.mm
        text "Den Medizinbogen, die Fotohinweise und das SEPA-Mandat im Anhang #{of_legal_age ? "habe ich" : "haben wir"} gesondert unterschrieben."

        pdf.move_down 3.mm
        if early_payer?(@person)
          text "Für die Zahlung des Teilnehmendenbeitrages #{of_legal_age ? "wünsche ich" : "wünschen wir"} Einmalzahlung im Januar 2026."
        else
          text "Für die Zahlung des Teilnehmendenbeitrages #{of_legal_age ? "wünsche ich" : "wünschen wir"} Ratenzahlung nach dem in den Reisebedingungen aufgeführten Ratenplan."
        end

        signature = if of_legal_age
          pdf.make_table([
            [{content: @person.town + " den #{Time.zone.today.strftime("%d.%m.%Y")}", height: 30}],
            ["______________________________", ""],
            [{content: @person.full_name, height: 30}, ""]
          ], cell_style: {width: 240, padding: 1, border_width: 0, inline_format: true})
        elsif @person.additional_contact_single
          pdf.make_table([
            [{content: @person.town + ", den " \
              + Time.zone.today.strftime("%d.%m.%Y"), height: 30}],
            %w[__________________________ __________________________],
            [{content: @person.additional_contact_name_a, height: 30}, @person.full_name]
          ], cell_style: {width: 240, padding: 1, border_width: 0, inline_format: true})
        else
          pdf.make_table([
            [{content: @person.town + ", den " + Time.zone.today.strftime("%d.%m.%Y"), height: 30}],
            %w[__________________________ __________________________ __________________________],
            [{content: @person.additional_contact_name_a, height: 30}, @person.additional_contact_name_b, @person.full_name]
          ], column_widths: [150, 150, 150], cell_style: {padding: 1, border_width: 0, inline_format: true})
        end

        pdf.move_down 3.mm

        signature.draw

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
