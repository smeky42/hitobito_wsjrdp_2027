# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Foto < Section
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

        signature = if of_legal_age
          pdf.make_table([
            [{content: @person.town + " den #{Time.zone.today.strftime("%d.%m.%Y")}", height: 30}],
            ["______________________________", ""],
            [{content: @person.full_name, height: 30}, ""]
          ],
            cell_style: {width: 240, padding: 1, border_width: 0,
                         inline_format: true})
        elsif @person.additional_contact_single
          pdf.make_table([
            [{content: @person.town + " den " \
              + Time.zone.today.strftime("%d.%m.%Y"), height: 30}],
            %w[__________________________ __________________________],
            [{content: @person.additional_contact_name_a, height: 30}, \
              + @person.full_name]
          ],
            cell_style: {width: 240, padding: 1, border_width: 0,
                         inline_format: true})
        else
          pdf.make_table([
            [{content: @person.town + " den " \
              + Time.zone.today.strftime("%d.%m.%Y"), height: 30}],
            %w[__________________________ __________________________],
            [{content: @person.additional_contact_name_a, height: 30}, \
              + @person.additional_contact_name_b],
            ["______________________________", ""],
            [{content: @person.full_name, height: 30}, ""]
          ],
            cell_style: {width: 240, padding: 1, border_width: 0,
                         inline_format: true})
        end

        text "Was muss ich mit der Fotoeinwilligung machen?", size: 12
        text "Die Fotohinweise und Erlaubnis muss"
        text "1. vollständig unterschrieben werden"
        text '2. auf anmeldung.worldscoutjamboree.de unter "Upload>Fotoerlaubnis" hochgeladen werden'
        text "3. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden"

        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        if !@person.foto_permission
          text "Widerspruch zur", size: 12
        end

        text "Anfertigung von Bild- und Tonaufnahmen (Fotoeinwilligung)", size: 12

        pdf.move_down 3.mm
        text "Der rdp wird die Veranstaltung und die Vorbereitungstreffen mit Bild- und Tonaufnahmen für die Selbst- und Außendarstellung dokumentieren. Solche Aufnahmen dürfen nur mit Einwilligung der abgebildeten Person (bzw. deren Sorgeberechtigten) angefertigt und verarbeitet werden."

        if !@person.foto_permission
          pdf.move_down 3.mm
          text "#{of_legal_age ? "Ich bin" : "Wir sind"} nicht damit einverstanden, dass der Veranstalter Fotos und Videos, auf denen #{of_legal_age ? "ich zu sehen bin" : "unser Kind zu sehen ist"}, anfertigt und bearbeitet."

          pdf.move_down 3.mm
          text "Da die Einwilligung nicht erteilt wird, wird die Unitleitung die vom Veranstalter beauftragten Fotograf*innen anweisen, entsprechende Teilnehmer*in nicht zu fotografieren. Der Veranstalter wird alle zumutbaren Anstrengungen unternehmen, um diesen Wunsch zu respektieren. Um dies für alle Beteiligten zu erleichtern, können Teilnehmer*innen, die nicht fotografiert werden möchten, auf Wunsch ein spezielles Erkennungszeichen (z.B. ein farbiges Armband oder Lanyard) erhalten, welches sie während der Veranstaltung tragen."

          pdf.move_down 3.mm
          text "#{of_legal_age ? "Ich habe" : "Wir haben"} die die folgenden Fotoeinwilligung gelesen und widerspreche ihr."

          pdf.move_down 3.mm
          if !@person.foto_permission
            signature.draw
          end

          pdf.move_down 3.mm

          pdf.stroke_horizontal_rule
          pdf.move_down 3.mm
          text "Anfertigung von Bild- und Tonaufnahmen (zur Information)", size: 12
        end

        pdf.move_down 3.mm
        text "#{of_legal_age ? "Ich bin" : "Wir sind"} damit einverstanden, dass der Veranstalter Fotos und Videos, auf denen #{of_legal_age ? "ich zu sehen bin" : "unser Kind zu sehen ist"}, "
        text "    • anfertigt und bearbeitet (z.B. durch Bildbearbeitung),"
        text "    • die so angefertigten oder bearbeiteten Bilder für eigene Zwecke verwendet, insbesondere Veröffentlichung in den Medien der Mitgliedsverbände (z.B. Zeitschrift, Newsletter), Veröffentlichung in der Presse (z.B. Pressefotos), Veröffentlichung im Internet (z.B. auf den Homepages des Veranstalters oder eines Mitgliedsverbands oder den jeweiligen Auftritten bei Facebook, Instagram etc.), Veröffentlichung in Werbemedien des Veranstalters oder eines Mitgliedsverbands (z.B. Flyer/Plakate) und"
        text "    • den Mitgliedsverbänden unentgeltlich zur Verfügung stellt. "

        pdf.move_down 3.mm
        text "Eine gezielte Übermittlung der personenbezogenen Daten in ein sog. Drittland ist nicht geplant."

        pdf.move_down 3.mm
        text "Hinweise zum Urheberrecht: Eine Vergütung wird nicht geleistet. #{of_legal_age ? "Ich räume" : "Wir räumen"} mit Abgabe der Einwilligung dem Veranstalter zugleich die erforderlichen einfachen Nutzungsrechte für die geplante Verwendung im Internet, „Social Media“ oder im Printbereich ein."

        pdf.move_down 3.mm

        text "Soweit aus dem Foto oder Video Angaben zur rassischen und ethnischen Herkunft, zu politischen Meinungen, zu religiösen oder weltanschaulichen Überzeugungen oder Gesundheit #{of_legal_age ? "von mir" : "des*der Teilnehmeri*n"}  zu entnehmen sind, bezieht sich meine Einwilligung auch auf diese Angaben."

        pdf.move_down 3.mm
        text "Die Einwilligung kann jederzeit ganz oder teilweise mit Wirkung für die Zukunft widerrufen, etwa per E-Mail an media-info@worldscoutjamboree.de. In diesem Fall werden Aufnahmen, die #{of_legal_age ? "mich" : "den*die Teilnehmer*in"} zeigen, vom Veranstalter von den Internetseiten und – soweit dieser verantwortlich sind – auch von den betreffenden „Social Media“-Diensten entfernt. Sollten Aufnahmen in Printprodukten verwendet worden sein, dürfen bereits gedruckte Exemplare weiterverwendet werden. Bei einer Neuauflage wird berücksichtigt, dass das Foto nicht wieder erscheint."

        text "Unabhängig hiervon werden Bild- und Tonaufnahmen der Teilnehmer*innen gelöscht, sobald sie nicht mehr für Zwecke der Dokumentation der Veranstaltung oder für die Außendarstellung des rdp benötigt werden. "

        pdf.move_down 3.mm
        text "Wenn die Einwilligung nicht erteilt wird, wird die Unitleitung die vom Veranstalter beauftragten Fotograf*innen anweisen, #{of_legal_age ? "mich" : "den*die Teilnehmer*in"} nicht zu fotografieren. Der Veranstalter wird alle zumutbaren Anstrengungen unternehmen, um diesen Wunsch zu respektieren. Um dies für alle Beteiligten zu erleichtern, können Teilnehmende, die nicht fotografiert werden möchten, auf Wunsch ein spezielles Erkennungszeichen (z.B. ein farbiges Armband oder Lanyard) erhalten, welches sie während der Veranstaltung tragen."

        pdf.move_down 3.mm
        text "Fragen zu der Anfertigung von Bild- und Tonaufnahmen und zu deren Verwendung können an die E-Mail-Adresse media-info@worldscoutjamboree.de gerichtet werden."

        pdf.move_down 3.mm
        if @person.foto_permission
          signature.draw
        end

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
