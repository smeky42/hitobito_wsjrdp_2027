# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Contract < Section
      # include FinanceHelper

      # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
      def render
        pdf.y = bounds.height - 60
        bounding_box([0, 230.mm], width: bounds.width, height: bounds.height - 200) do
          font_size(8) do
            text list, style: :italic, width: bounds.width
          end
        end
      end

      def list
        pdf.move_down 3.mm
        text "Was muss ich mit der Anmeldung machen?", size: 12
        text "Die Anmeldung muss"
        text "1. vollständig unterschrieben werden"
        text "2. auf anmeldung.worldscoutjamboree.de unter " \
        + '"Upload>Anmeldung hochladen" hochgeladen werden'
        text "3. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden"
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        text "Anmeldung", size: 12

        text "von " + @person.full_name + ", geboren am " + @person.birthday.strftime("%d.%m.%Y") \
        + ", wohnhaft in " + @person.address + ", " + @person.zip_code + ", " + @person.town

        pdf.start_new_page
        pdf.move_down 3.mm
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
        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
