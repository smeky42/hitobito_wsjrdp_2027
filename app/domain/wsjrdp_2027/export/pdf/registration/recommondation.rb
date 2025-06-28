# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Recommondation < Section
      self.name = "Empfehlungsschreiben"

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
        text "Was muss ich der Handreichung zum Empfehlungsschreiben: machen?", size: 12
        text "Die Handreichung zum Empfehlungsschreiben: muss"
        text "1. mit dem Empfehlungsschreiben einer Leitungsperson über dir vorgelegt werden"
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        text "Handreichung zum Empfehlungsschreiben:", size: 12
        pdf.move_down 3.mm
        text "Im Sommer 2027 findet das 26. World Scout Jamboree in Polen statt. Wir als Ring deutscher Pfadfinder*innen wollen aus unserem Selbstverständnis heraus dort gemeinsam als deutsche Pfadfinder*innen auftreten."
        pdf.move_down 3.mm
        text "Unser Ziel ist es, dass für alle Units des verbandsübergreifenden deutschen Kontingents (German Contingent) die gleichen Maßstäbe, Kosten und Vorbereitungsstandards gelten und die Jugendlichen durch ein Team aus vier Unit Leadern auf ihrem Erlebnis Jamboree bestmöglich vorbereitet, unterstützt und geleitet werden."
        pdf.move_down 3.mm
        text "Da für die Mitglieder*innen der Unitleitung die langfristige Übernahme von Verantwortung sowie Zuverlässigkeit, Teamfähigkeit und weitere Kompetenzen erforderlich sind, gehört zu unserem Anmelde- und Auswahlverfahren für Unit Leader eine Empfehlung für die jeweilige Person. Dies erfolgt durch eine Person der nächst höheren Ebene des jeweiligen Verbandes (VCP, BdP, BMPPD, DPSG). Gemeinsam soll in einem Gespräch und aus vorangegangenen Erfahrungen bewertet werden, ob der*die Bewerber*in geeignet ist, Teil eines Unitleitungsteams auf dem World Scout Jamboree 2027 zu sein. Potentielle Themen für ein solches Gespräch sind eine Reflexion der bisherigen Leitungserfahrung, ob bereits Jamboree Erfahrung vorliegt oder die Motivation der Bewerbung. Außerdem soll bestätigt werden, dass für den*die Bewerber*in die entsprechende Jugenleitungsausbildung als Grundvoraussetzung vorliegt oder bis Januar 2026 fest geplant ist. Für das Gespräch haben wir euch weitere Impulsfragen beigefügt, die euch helfen können."
        pdf.move_down 3.mm
        text "Schon einmal ein herzliches Dankeschön dafür, dass du uns bei der Suche geeigneter Unit Leader unterstützt!"
        pdf.move_down 3.mm
        text "Impulsfragen für das Gespräch"
        text "    • Welche Gruppenleitungstätigkeiten habe ich bisher gemacht?"
        text "    • Kann ich auch unter Stress einen kühlen Kopf bewahren?"
        text "    • Schaffe ich es, die nächsten zwei Jahre das Amt des Unit Leaders mit meinem restlichen Leben (Studium/ Arbeit/ Ausbildung) zu vereinbaren?"
        text "    • Habe ich bereits Erfahrungen im verbandsübergreifenden Kontext gemacht?"
        text "    • Welche Vorstellung habe ich davon, ein Unit Leader zu sein?"
        text "    • Welche Stärken kann ich in die Unitleitung einbringen?"
        text "    • Bin ich bereit unter Einsatz der englischen Sprache und Händen und Füßen mich auf einem Zeltplatz mit einem Anliegen durchzufragen?"
        text "    • Welche meiner Schwächen stellen eine Hürde für mich als Unit Leader dar und wie möchte ich mit diesen Umgehen?"
        text "    • Was motiviert mich das Amt des Unit Leaders übernehmen zu wollen?"

        pdf.move_down 3.mm

        pdf.start_new_page

        text "Was muss ich mit diesem Empfehlungsschreiben machen?", size: 12
        text "Das Empfehlungsschreiben muss"
        text "1. einer Leitungsperson über dir vorgelegt werden"
        text "2. vollständig von der Leitungsperson ausgefüllt und unterschrieben werden"
        text '3. auf anmeldung.worldscoutjamboree.de unter "Upload>Empfehlungsschreiben hochladen" hochgeladen werden'
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule
        pdf.move_down 3.mm
        text "Empfehlungschreiben:", size: 12

        pdf.move_down 3.mm

        text "Hiermit bestätige ich, ", leading: 20
        text "______________________________,"
        text "(Name)", size: 6, leading: 20
        text "als ______________________________,"
        text "(Amt)", size: 6, leading: 20
        text "der / des ______________________________,"
        text "(Ebene z.B  Stamm, Bezirk/Region/Gau, Diözese/Land) ", size: 6, leading: 20
        text "im Verband ______________________________, "
        pdf.move_down 3.mm
        text "dass #{@person.full_name} eine Jugendleitungsausbildung, die ihn*sie zur Beantragung einer JuLeiCa (Jugendleiter*in-Card) befähigt oder plant diese bis zum Januar 2026 abzuschließen."
        pdf.move_down 3.mm
        text "Des weitern halte ich #{@person.full_name} für geeignet, Mitglied einer Unitleitung für das World Scout Jamboree 2027 zu sein. Sie*er bringt die notwendigen Kompetenzen für diese Aufgabe mit und kann dadurch für seine Unit zu einem unvergesslichem Jamboreeerlebnis maßgeblich beitragen."

        pdf.move_down 3.mm
        pdf.make_table([
          [{content: "Unteschrift der Leitungsperson",
            height: 30}],
          ["______________________________", ""],
          [{content: "Ort, Datum", height: 30}, ""]
        ],
          cell_style: {width: 240, padding: 1, border_width: 0,
                       inline_format: true}).draw

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
