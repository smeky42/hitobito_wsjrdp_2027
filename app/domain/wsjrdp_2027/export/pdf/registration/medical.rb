# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Medical < Section
      def render
        pdf.y = bounds.height - 60
        bounding_box([0, 230.mm], width: bounds.width, height: bounds.height - 200) do
          font_size(8) do
            text content, width: bounds.width
          end
        end
      end

      def content
        of_legal_age = @person.years.to_i >= 18

        text "Was muss ich mit dem Medizinbogen machen?", size: 12
        text "Der Medizinbogen muss"
        text "1. vollständig unterschrieben werden"
        text "2. am ersten Treffen der entsprechenden Betreuungsperson im Orginal überreicht werden"
        text "3. Änderungen bis zum Antritt der Reise über die Anmeldung (anmeldung.worldscoutjamboree.de) mitgeteilt werden."
        pdf.move_down 3.mm
        pdf.stroke_horizontal_rule

        pdf.move_down 3.mm
        text "Medizinbogen", size: 12

        pdf.move_down 1.mm
        text "von #{@person.full_name}, geboren am #{@person.birthday.strftime("%d.%m.%Y")}"
        pdf.move_down 1.mm
        text "Ansprechpartner*innen im Notfall"
        pdf.move_down 1.mm
        # TODO detection which contacts to print
        text "#{@person.additional_contact_name_a}, #{@person.additional_contact_phone_a}, #{@person.additional_contact_adress_a}"
        text "#{@person.additional_contact_name_b}, #{@person.additional_contact_phone_b}, #{@person.additional_contact_adress_b}"
        pdf.move_down 3.mm
        text "Telefonnummern"
        pdf.move_down 1.mm
        @person.phone_numbers.each do |phone|
          text "#{phone.label}: #{phone.number}"
        end
        pdf.move_down 3.mm

        text "Damit die Gesundheit der Teilnehmer*innen auch bei medizinischen Notfällen gewährleistet werden kann, müssen die folgenden Fragen wahrheitsgemäß und vollständig beantwortet werden. Der rdp stellt durch technische und organisatorische Maßnahmen sicher, dass der Schutz der nachfolgend erhobenen Gesundheitsdaten gewährleistet wird. Weitere Informationen finden sich in den Hinweisen zur Datenverarbeitung."

        pdf.move_down 3.mm
        text "Grundsätzliches", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Änderungen müssen bis zum Antritt der Reise unverzüglich dem Veranstalter/dem ärztlichen Team über die Anmeldung (anmeldung.worldscoutjamboree.de) mitgeteilt werden."
        pdf.move_down 1.mm
        text "Krankenversicherungskarte und Impfausweis sind mitzuführen. Der Gesundheitsbogen ist von der Unitleitung mitzuführen. Auf dem Gesundheitsbogen werden sensible Daten erfasst. Wir benötigen diese zur Durchführung der Reise und für den Veranstalter des World Scout Jamborees. Wir verfahren sehr sorgfältig mit den Daten, mehr dazu findet sich in unseren Datenschutzhinweisen in den Reisebedingungen."

        pdf.move_down 3.mm
        text "Schutzimpfungen", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Nur im Impfausweis dokumentierte Impfungen gelten als durchgeführt."
        pdf.move_down 1.mm
        text "<strong>Die von der STIKO empfohlenen Schutzimpfungen wurden geimpft:</strong> #{@person.medical_stiko_vaccinations ? "Ja" : "Nein"}", inline_format: true
        pdf.move_down 1.mm
        text "Folgende Impfungen/Grundimmunisierung werden unsererseits empfohlen: Hepatitis A & B. Außerdem werden reisemedizinisch für Touristen bei einfachen Reisen für Polen (Stand 31.04.2025) weitere Impfungen empfohlen: FSME. Da auf dem Jamboree Kontakt zu Jugendlichen aus allen Teilen der Erde bei einfachen hygienischen Verhältnissen besteht, ist auch Kontakt zu für Europa untypischen Erkrankungen denkbar. Eine Beratung zu weiteren Impfungen nach individuellem Risiko durch den Kinder- oder Hausarzt wird empfohlen."
        pdf.move_down 1.mm
        text "Weitere Impfungen (Impfdatum Monat/Jahr)", style: :bold
        text @person.medical_additional_vaccinations.presence || "---"

        pdf.move_down 3.mm
        text "Medizinische Angaben", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Bekannte Vorerkrankungen / Operationen / Kinderkrankheiten", style: :bold
        text @person.medical_preexisting_conditions.presence || "---"
        pdf.move_down 1.mm
        text "Folgende Auffälligkeiten / Erkrankungen sind bekannt (z.B. Asthma, Reisekrankheit, Epilepsie, Angststörung, AD(H)S, erhöhter Betreuungsaufwand, etc.)", style: :bold
        text @person.medical_abnormalities.presence || "---"
        pdf.move_down 1.mm
        text "Es bestehen folgende Allergien (z.B. gegen Medikamente, nachgewiesene Lebensmittelallergien, Heuschnupfen, etc.) mit folgenden Symptomen", style: :bold
        text @person.medical_allergies.presence || "---"
        pdf.move_down 1.mm
        text "Es bestehen folgende Essensbesonderheiten (ggf. mit folgenden Symptomen)", style: :bold
        text @person.medical_eating_disorders.presence || "---"
        pdf.move_down 1.mm
        text "Es bestehen folgende Mobilitätsbedürfnisse auf Grund von", style: :bold
        text @person.medical_mobility_needs.presence || "---"
        pdf.move_down 1.mm
        text "Es besteht eine infektiöse Erkrankung, vor der andere Menschen oder medizinisches Personal besonders geschützt werden müssen (z.B. meldepflichtige Erkrankungen, Tuberkulose, Hepatitis B/C, HIV etc.)", style: :bold
        text @person.medical_infectious_diseases.presence || "---"
        pdf.move_down 1.mm
        text "Zurzeit in ärztlicher Behandlung bei (behandelnde*r Ärzt*in mit Fachrichtung, Name, Kontaktdaten)", style: :bold
        text "Es wird bei Bedarf gestattet, dass sich das ärztliche Team des CMT mit dem genannten med. Fachpersonal in Kontakt setzt, um Gesundheitsdaten / Informationen auzutauschen (Schweigepflichtentbindung)."
        text @person.medical_medical_treatment_contact.presence || "---"

        pdf.move_down 3.mm
        text "Medikamente", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Mein / Unser Kind bekommt folgende Medikamente."
        pdf.move_down 1.mm
        text "Dauermedikation (Dosierung / Einnahmeschema / Einnahmegrund)", style: :bold
        text @person.medical_continuous_medication.presence || "---"
        pdf.move_down 1.mm
        text "Bedarfmedikation (Dosierung / Tageshöchstmenge / Einnahmegrund)", style: :bold
        text @person.medical_needs_medication.presence || "---"
        pdf.move_down 1.mm
        text "Es werden folgende Medikamente selbstständig eingenommen", style: :bold
        text @person.medical_self_treatment_medication.presence || "---"
        pdf.move_down 1.mm
        text "Mit dem Hausarzt ist abzuklären, ob für die bestehende Dauer- & Bedarfsmedikation ein aktueller Medikamentenplan der Medikamente mitgeführt werden muss. Sollten spezielle Lagerungsbedingungen für Medikamente benötigt werden (z.B. Kühlung), bitte frühzeitig unter info@worldscoutjamboree.de melden."

        pdf.move_down 3.mm
        text "Wellbeing – durch die Teilnehmenden selbst auszufüllen", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Uns ist es wichtig, dass sich alle Teilnehmenden während der Reise wohlfühlen und die gemeinsame Zeit genießen können. Wir wissen aber auch: Eine lange Reise in ein fremdes Land, in einer neuen Gruppe, kann manchmal sehr herausfordernd sein."
        pdf.move_down 1.mm
        text "Damit wir dich bestmöglich unterstützen können, wenn es nötig wird, möchten wir dir die Möglichkeit geben, uns im Vorfeld ein paar Informationen mitzuteilen. Unser Wellbeing-Team besteht aus Fachpersonen für psychische Gesundheit und ist jederzeit ansprechbar, wenn du Unterstützung brauchst. Gerne kannst du auch schon im Vorfeld das Gespräch zu uns suchen, dann können wir gemeinsam überlegen, wie wir dich in schwierigen Situationen unterstützen."
        pdf.move_down 1.mm
        text "Gibt es etwas, das wir im Hinblick auf deine psychische Gesundheit wissen sollten?", style: :bold
        text "Dazu zählen zum Beispiel: erhöhte Stressbelastung, Depressionen, Angststörungen, ADHS, Persönlichkeitsmerkmale oder ein erhöhter Unterstützungsbedarf. Falls ja: Warst du deswegen bereits in Behandlung (z.B. durch Therapie, Medikamente oder einen Klinikaufenthalt)?"
        text @person.medical_mental_health.presence || "---"
        pdf.move_down 1.mm
        text "Was hilft dir, wenn du in stressige oder belastende Situationen gerätst? (Gibt es bestimmte Maßnahmen, Verhaltensweisen oder Unterstützung, die dir dann gut tun?)", style: :bold
        text @person.medical_situational_support.presence || "---"
        pdf.move_down 1.mm
        text "Möchtest du eine Vertrauensperson angeben, die dich in schwierigen Situationen unterstützen kann? (Bitte gib Name und Kontaktdaten an.)", style: :bold
        text @person.medical_person_of_trust.presence || "---"

        pdf.move_down 3.mm
        text "Hinweis", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Alle Angaben werden selbstverständlich vertraulich behandelt. Sie helfen uns lediglich dabei, dich auf der Reise bestmöglich zu begleiten und zu unterstützen. Wenn du Fragen hast oder etwas persönlich besprechen möchtest, kannst du dich gerne jederzeit an uns wenden. Weitere Infos findest du hier: https://www.worldscoutjamboree.de/youth-participants-mit-einschraenkungen/"

        pdf.move_down 3.mm
        text "Weitere Angaben", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Es ist auf Folgendes zu achten", style: :bold
        text @person.medical_other.presence || "---"

        pdf.move_down 3.mm
        text "Im Falle eines Falles", size: 10, style: :bold
        pdf.move_down 1.mm
        text "Im Falle einer Erkrankung oder eines Unfalles, bei denen durch eine Behandlung oder vorläufige Nicht-Behandlung in der Regel keine bleibenden Schäden zu erwarten sind (Bagatellerkrankungen/-verletzungen, Zecke/Splitter entfernen,...) darf unser Kind eigenständig über Behandlungen entscheiden und in medizinische Eingriffe einwilligen, da es die für eine solche Entscheidung notwendige persönliche geistige und körperliche Reife aufweist. Die Versorgung darf auch von Seiten der Betreuung erfolgen."
        pdf.move_down 1.mm
        text "Bei lebensbedrohlichen Erkrankungen / Unfällen entscheidet der behandelnde Arzt vor Ort."
        pdf.move_down 1.mm
        text "Wir haben den Gesundheitsfragebogen warheitsgemäß ausgefüllt. Wir sind damit einverstanden, dass die persönlichen Daten und so wie Behandlungsdaten zum Zwecke der gesetzlich vorgeschriebenen Dokumentation gespeichert werden. Nach Ablauf der gesetzlichen Aufbewahrungsfrist werden die Daten gelöscht."

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

        pdf.move_down 6.mm
        signature.draw

        pdf.move_down 3.mm
        text "Für Rückfragen stehen die Ärzte und das Wellbeing-Team des Kontingents unter medizin@worldscoutjamboree.de zur Verfügung"
      end
    end
  end
end
