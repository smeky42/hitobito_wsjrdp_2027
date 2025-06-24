# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class DataProcessing < Section
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
        text "Was muss ich mit dieser Vertraulichkeitsvereinbarung machen?", size: 12
        text "Die Vertraulichkeitsvereinbarung muss"
        text "1. vollständig unterschrieben werden"
        text '2. auf anmeldung.worldscoutjamboree.de unter "Upload>Vertraulichkeitsvereinbarung hochladen" hochgeladen werden'
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        text "Vertraulichkeitsvereinbarung", size: 12

        pdf.move_down 3.mm
        text "Zwischen dem Ring deutscher Pfadfinder*innenverbände e.V. (im Folgenden rdp) und #{@person.full_name}, im Folgenden Mitarbeitende*r."

        pdf.move_down 3.mm
        text "Im Rahmen der Tätigkeit für das Deutsche Kontingent zum World Scout Jamboree verarbeitet der/die Mitarbeitende auf Weisung des rdp e.V. personenbezogene Daten."

        pdf.move_down 3.mm
        text "Die einschlägigen gesetzlichen Vorschriften verlangen, dass personenbezogene Daten so verarbeitet werden, dass die Rechte der durch die Verarbeitung betroffenen Personen auf Vertraulichkeit und Integrität ihrer Daten gewährleistet werden. Daher ist es dem/der Mitarbeitende*n nur gestattet, personenbezogene Daten in dem Umfang und in der Weise zu verarbeiten, wie es zur Erfüllung der Aufgaben des/der Mitarbeitenden im rdp erforderlich ist. Die zugänglich gemachten personenbezogenen Daten dürfen ausschließlich für die Durchführung der Veranstaltung verwendet werden."

        pdf.move_down 3.mm
        text "Nach diesen Vorschriften ist es untersagt, personenbezogene Daten unbefugt oder unrechtmäßig zu verarbeiten oder absichtlich oder unabsichtlich die Sicherheit der Verarbeitung in einer Weise zu verletzen, die zur Vernichtung, zum Verlust, zur Veränderung, zur unbefugter Offenlegung oder unbefugtem Zugang führt."

        pdf.move_down 3.mm
        text "Verstöße gegen die Datenschutzvorschriften können ggf. mit Geldbuße, Geldstrafe oder Freiheitsstrafe geahndet werden. Entsteht der betroffenen Person durch die unzulässige Verarbeitung ihrer personenbezogenen Daten ein materieller oder immaterieller Schaden, kann ein Schadenersatzanspruch entstehen."

        pdf.move_down 3.mm
        text "Die Verpflichtung auf die Vertraulichkeit besteht auch nach der Beendigung der Tätigkeit für den rdp fort."

        pdf.move_down 3.mm
        text "Im Rahmen der Tätigkeit unterliegt die/der Mitarbeitende den Weisungen des rdp. Diese Vereinbarung wird auch ohne Unterschrift durch den rdp mit Unterzeichnung durch den/die Mitarbeitende*n wirksam."

        pdf.move_down 3.mm

        text "Ich, #{@person.full_name} erkläre, in Bezug auf die Vertraulichkeit und Integrität personenbezogener Daten die Vorgaben der geltenden Datenschutzvorschriften einzuhalten."

        pdf.move_down 3.mm
        pdf.make_table([
          [{content: @person.town + " den " + Time.zone.today.strftime("%d.%m.%Y"),
            height: 30}],
          ["______________________________", ""],
          [{content: @person.full_name, height: 30}, ""]
        ],
          cell_style: {width: 240, padding: 1, border_width: 0,
                       inline_format: true}).draw

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
