# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Travel < Section
      include ContractHelper

      self.name = "Teilnahme- und Reisebedingungen"

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
        pdf.move_down 3.mm
        text "Teilnahme- und Reisebedingungen für die Teilnahme im Deutschen Kontingent zum 26. World Scout Jamboree 2027 in Polen", size: 12

        pdf.move_down 3.mm
        text "Begriffserklärung", size: 10
        text "Im Rahmen dieser Reisebedidungen werden die folgenden Begriffe für verschiedene Rollen im Kontingent verwendet "
        text "    • Youth Participant (kurz YP): Jugendliche im Alter von 14 bis 18 Jahren"
        text "    • Unit Leaders (kurz UL): Volljährige Unitleiter*innen"
        text "    • Contingent Management Team (kurz CMT). VOlljährige Mitglieder des Kontingentsteams"
        text "    • International Service Team (kurz IST): Volljährige Mitglieder des International Service Teams"
        text "    • Head of Contingent (kurz HOC): Kontingentsleitung des deuschen Kontingents. Sind Mitglieder des CMT"
        text "Das Wort Teilnehmender*in umfasst im Folgenden alle Rollen (Youth Participants, IST, ULs, CMTs)."

        pdf.move_down 3.mm
        text "1. Veranstalter", size: 10
        text "Ringe deutscher Pfadfinder*innenverbände e.V. (rdp),"
        text "vertreten durch Sebastian Becker, Alexander Schmidt, Leah Albrecht, Susanne Rüber und Naima Hartit"
        text "Chausseestraße 128/129"
        text "10115 Berlin"
        text "Telefonnummer Büro: +49 30 288 7895 35"

        pdf.move_down 3.mm
        text "1.1 Organisation / Kontakt"
        text "Organisatorischer Ansprechpartner ist neben dem Veranstalter, die Kontingentsleitung (genannt Head of Contingent, kurz HOC) zum World Scout Jamboree 2027. Das HOC ist wie folgt zu erreichen:"
        text "E-Mail: info@worldscoutjamboree.de"
        text "Weitere Kontaktdaten finden sich auf der Homepage: www.worldscoutjamboree.de"

        pdf.move_down 3.mm
        text "2. Reisezeitraum", size: 10
        text "Die Fahrt des rdp-Kontingents ist für den Zeitraum vom 20.07. bis 18.08.2027 geplant. Der Reisezeitraum variiert je nach gewähltem Paket und Lage der Sommerferien. Die Reisedauer beträgt in der Regel 17-21 Tage, kann aber für eine Unit durch die Unitleitungen nach Genehmigung der Kontingentsleitung verlängert werden, wenn für die Teilnehmenden keine Zusatzkosten entstehen.  Die genauen Reisedaten werden im Herbst 2026 feststehen, da erst zu diesem Zeitpunkt die tatsächlichen An-/Abreisedaten festgelegt werden können. Die Teilnehmenden werden über die in der Anmeldung angegebenen Mailadressen über die Reisedaten informiert."

        pdf.move_down 3.mm
        text "3. Reiseziel, Reiseform, Pakete", size: 10

        pdf.move_down 3.mm
        text "3.1 Das Reiseland ist die Republik Polen und je nach Etappen der Unittour die angrenzende Tschechische Republik und die Slowakische Republik, jedoch innerhalb der Europäischen Union. Nach Abschluss der Planung werden genaue Reisedetails bekannt gegeben."

        pdf.move_down 3.mm
        text "3.2 Die Teilnahme am World Scout Jamboree 2027 unterscheidet sich je nach Rolles im Deutschen Kontingent.  Es gibt jeweils Reisepakete für:"

        pdf.move_down 3.mm
        text "a) Teilnehmende in Units (UL und YP)"
        text "Die Reise von YP und UL findet in ihren Units statt. Eine Unit besteht regelmäßig aus 36"
        text "YP im Alter zwischen 14 - 18 Jahren und 4 ULs. Die Zuteilung in Units wird vom"
        text "CMT ab Herbst 2025 unter Berücksichtigung der Wünsche der Teilnehmenden vorgenommen. Vor der Reise nach Polen finden verbindliche Vorbereitungstreffen in der zugeteilten Unit statt, die mehrere Wochenenden umfassen. Die Termine werden von der jeweiligen ULs der Unit mitgeteilt. Die Teilnahme an den Vorbereitungstreffen ist Voraussetzung für die Teilnahme am Jamboree."

        pdf.move_down 3.mm
        text "b) CMT und IST"
        text "Für CMT und IST finden Vor- und/oder Nachprogramm sowie die An- und Abreiseplanung in Eigenregie statt. Sie sind nicht im Reisepreis inbegriffen. Planung und Durchführung von Vor- und/oder Nachprogramm kann in Kleingruppen mit anderen Mitgliedern des Kontingents geschehen. Das Kontingent bietet auf den Vorbereitungstreffen die Möglichkeit, Gruppen hierfür zu bilden. Vor der Reise nach Polen finden verbindliche Vorbereitungstreffen statt, die mehrere Wochenenden umfassen. Die Termine werden vom HOC mitgeteilt. Die Teilnahme an den Vorbereitungstreffen ist Voraussetzung für die Teilnahme am Jamboree."

        pdf.move_down 3.mm
        text "4. Teilnahmebedingungen", size: 10

        pdf.move_down 3.mm
        text "4.1 YP müssen zwischen dem 30.07.2009 und dem 30.07.2013 geboren sein. Erwachsene können nur als UL, CMT oder IST am Jamboree teilnehmen und damit die Durchführung unterstützen."

        pdf.move_down 3.mm
        text "4.2 Eine aktive Mitgliedschaft in einem der folgenden Pfadfinder*innenverbände ist Voraussetzung für die Teilnahme:"
        text "- Bund der Pfadfinderinnen und Pfadfinder e.V. (BdP),"
        text "- Bund Muslimischer Pfadfinder und Pfadfinderinnen Deutschlands e.V. (BMPPD),"
        text "- Deutsche Pfadfinderschaft Sankt Georg / Bundesamt Sankt Georg e.V. (DPSG),"
        text "- Pfadfinderinnenschaft Sankt Georg / Pfadfinderinnenwerk St. Georg e.V. (PSG),"
        text "- Verband Christlicher Pfadfinder*innen (VCP) e.V."

        pdf.move_down 3.mm
        text "4.3 Die Teilnahme am Jamboree setzt voraus, dass der*die YP an mindestens zwei Vorbereitungstreffen teilnimmt. Die Daten zu den Vorbereitungstreffen werden den YPs von der jeweiligen ULs bekannt gegeben."

        pdf.move_down 3.mm
        text "4.4 Die*Der YP ist selbst dafür verantwortlich, die erforderlichen Reisedokumente und Einreisegenehmigungen zu beschaffen. Deutsche Staatsangehörige benötigen für die Einreise einen für die Dauer des Aufenthaltes gültigen Reisepass oder Personalausweis. Staatsbürger*innen anderer Nationen informieren sich bitte rechtzeitig, welche Dokumente sie benötigen."

        pdf.move_down 3.mm
        text "4.5 Für die gesundheitliche Betreuung steht während des Jamborees das Jamboree-Hospital (medizinische Erstversorgungseinrichtung) und nach Möglichkeit zwei deutschsprachige Kontingentsärzt*innen als Ansprechpartner*innen zur Verfügung. Kosten für außerplanmäßige Rückreisen nach ärztlicher Indikationsstellung werden nicht vom Teilnahmepreis abgedeckt."

        pdf.move_down 3.mm
        text "5. Anmeldung und Vertragsschluss", size: 10

        pdf.move_down 3.mm
        text "5.1 Die Anmeldung ist bis spätestens zum 15.10.2025 über die Homepage anmeldung.worldscoutjamboree.de möglich. Sollte während der Anmeldephase die vom CMT festgelegte Maximalanzahl an Teilnehmer*innen überschritten werden, kann die Anmeldung schon früher geschlossen werden. Während des Online-Anmeldeprozesses wird eine PDF-Dokument generiert, das die anmeldende Person lesen und akzeptieren muss. Das Anmeldungsdokument muss unterschrieben werden und spätestens bis zum Anmeldeschluss am 15.10.2025 über die Homepage hochgeladen werden. Die Anmeldung muss im Original (Papierform mit Unterschriften) spätestens zum 01.06.2026 bei den entsprechenden Betreuer*innen (UL für YPs, IST-Betreuung für IST, CMT Management für UL und CMT) abgegeben werden."
        text "Bei Personen, die zum Zeitpunkt der Anmeldung das 18. Lebensjahr noch nicht vollendet haben, muss die Anmeldung durch alle Personensorgeberechtigten unterzeichnet sein. "

        pdf.move_down 3.mm
        text "5.2 Ein Vertrag über die Teilnahme kommt erst dann zustande, wenn der rdp die Anmeldung in Textform (z.B. E-Mail) bestätigt. Dies erfolgt erst nach Anmeldeschluss. Eine Anmeldung ist keine Garantie für die tatsächliche Teilnahme, insbesondere bei Überschreiten der Maximalanzahl an Teilnehmer*innen."

        pdf.move_down 3.mm
        text "6. Teilnahmebeitrag, Preiserhöhungen, Änderung der Reisebedingungen", size: 10

        pdf.move_down 3.mm
        text "6.1 Der Teilnahmebetrag richtet sich nach der gewählten Teilnahmevariante (s.o. Ziff. 3.2, Reiseform und Pakete) und ggf. nach der Funktion der*des Teilnehmerin*s im Kontingent. Das SEPA Lastschriftverfahren wird je nach gewähltem Zahlungsmodell in Raten oder einmalig eingezogen. Der Einzug erfolgt am 5. des jeweiligen Monats bzw. am darauffolgenden Werktag. "

        pdf.move_down 3.mm
        text "Bei Wahl des Ratenzahlungsmodells:"
        pdf.make_table(payment_array_sepa.slice!(0, 5), cell_style: {padding: 1,
                                                                     border_width: 0,
                                                                     inline_format: true,
                                                                     size: 8}).draw

        pdf.move_down 3.mm
        text "Bei Wahl des Einmalzahlungsmodells am 5. August 2025 (bei Anmeldung bis Ende Juli) oder am 5. November 2025 (bei Anmeldung bis Ende August):"
        pdf.make_table(payment_array_sepa.slice!(5, 9), cell_style: {padding: 1,
                                                                     border_width: 0,
                                                                     inline_format: true,
                                                                     size: 8}).draw

        pdf.move_down 3.mm
        text "NICHT im Teilnahmebeitrag enthalten sind:"
        text "- Reiserücktrittversicherung"
        text "- Gepäckversicherung"
        text "- persönliche Ausgaben"
        text "- Kosten für Einreisegenehmigungen nach Polen (falls erforderlich)"
        text "Der Abschluss einer Reiserücktrittsversicherung wird dringend empfohlen."

        pdf.move_down 3.mm
        text "6.2 Sollten sich nach Bestätigung der Anmeldung durch den rdp wesentliche Umstände ändern, insbesondere Beförderungskosten, Steuern oder Wechselkurse, oder sollten sonstige Änderungen am Programm vorgenommen werden müssen, behält sich der rdp vor, den Teilnahmebeitrag um den jeweiligen Erhöhungsbetrag anzupassen. Ab dem 20. Tag vor Reiseantritt ist eine Preiserhöhung unzulässig. Überschreitet der Erhöhungsbetrag 5 % des ursprünglich vereinbarten Preises, ist der*die Teilnehmer*in nach Maßgabe von Ziff. 7.3 berechtigt, vom Vertrag zurückzutreten."

        pdf.move_down 3.mm
        text "6.3 Der Beitrag wir durch SEPA-Lastschriften nach dem vereinbarten Zahlungsmodell eingezogen. Hierfür ist die Erteilung eines SEPA-Basis-Lastschriftmandates erforderlich. "

        pdf.move_down 3.mm
        text "7. Rücktritt des Teilnehmenden vor Leistungsbeginn", size: 10

        pdf.move_down 3.mm
        text "7.1 Der*Die Teilnehmer*in kann jederzeit vor Beginn der Reise von dem Vertrag zurücktreten. Der Rücktritt ist in Textform gegenüber dem rdp via E-Mail an info@worldscoutjamboree.de oder postalisch (Ringe deutscher Pfadfinder*innenverbände e.V. (rdp), Chausseestraße 128/129, 10115 Berlin) zu erklären."

        pdf.move_down 3.mm
        text "7.2 Erklärt der*die Teilnehmer*in den Rücktritt, so verliert der rdp den Anspruch auf Zahlung des Teilnehmerbeitrages. Stattdessen kann der rdp eine angemessene Entschädigung verlangen, sofern der Rücktritt nicht von ihm zu vertreten ist. Die Höhe der Entschädigung ist pauschaliert wie folgt:"
        text "    • bei Rücktritt bis zum 31.05.2026: 50% des Teilnahmebeitrags"
        text "    • bei Rücktritt bis zum 31.12.2026: 75% des Teilnahmebeitrags"
        text "    • bei Rücktritt bis zum 31.03.2027: 90% des Teilnahmebeitrags"
        text "    • nach diesem Zeitpunkt in Höhe des vollen Teilnahmebeitrags"
        text "Dem*Der Teilnehmer*in bleibt der Nachweis unbenommen, dem rdp sei durch den Rücktritt kein Schaden entstanden oder der Schaden sei wesentlich geringer als die oben genannten Pauschalsätze. "

        pdf.move_down 3.mm
        text "7.3 Wenn der rdp von der ihm eingeräumten Möglichkeit Gebrauch macht, den Teilnahmebeitrag um mehr als 5 % gegenüber dem ursprünglich geltenden Preis zu erhöhen, und erklärt der*die Teilnehmer*in deshalb den Rücktritt, ist eine Entschädigung nicht geschuldet; der*die Teilnehmer*in schuldet aber Ausgleich für Teilleistungen, die er bis zum Rücktritt in Anspruch genommen hat. Das gleiche gilt für den Fall, dass der*die Teilnehmer*in mit ergänzenden Bedingungen, die der rdp aufgrund von Vorgaben des polnischen Veranstalters weiterreichen muss, nicht einverstanden ist."

        pdf.move_down 3.mm
        text "7.4 Der rdp behält sich das Recht vor, anstelle der Entschädigung nach Ziff. 8.2 Schadensersatz zu verlangen, soweit er nachweisen kann, dass aufgrund des Rücktritts oder des Nichtantritts der Reise wesentlich höhere Aufwendungen oder ein wesentlich höherer Schaden entstanden sind."

        pdf.move_down 3.mm
        text "8. Kündigung und Rücktritt durch den rdp", size: 10

        pdf.move_down 3.mm
        text "8.1 Der rdp ist berechtigt, den Vertrag ohne Einhaltung einer Frist zu kündigen, wenn der*die Teilnehmer*in nachhaltig gegen seine im Reisevertrag und diesen Reisebedingungen vereinbarten Pflichten verstößt oder sonst durch sein Verhalten die Durchführung und den Erfolg der Veranstaltung nachhaltig gefährdet. Das ist insbesondere der Fall,"
        text "- wenn der*die Teilnehmer*in entgegen 4.3 bei mehr als zwei Vorbereitungstreffen unentschuldigt gefehlt hat, oder"
        text "- wenn der*die Teilnehmer*in gegen die Satzung seines Mitgliedsverbandes 4.2 verstößt, die Mitgliedschaft aufgibt oder sie verliert"
        text "Die Kündigung ist nur zulässig, wenn der rdp den*die Teilnehmer*in zuvor in Textform (z.B. durch eine Email) abgemahnt hat und der*die Teilnehmer*in sein Fehlverhalten dennoch fortsetzt. Eine vorherige Abmahnung ist nicht erforderlich in Fällen gröbsten Fehlverhaltens, in denen eine sofortige Aufhebung des Vertrages auch unter Berücksichtigung der Interessen des Teilnehmers gerechtfertigt ist."

        pdf.move_down 3.mm
        text "8.2 Der rdp ist zur Kündigung des Vertrages weiter dann berechtigt, wenn Lastschriften nicht eingelöst werden oder ihnen widersprochen wurde und auch nach schriftlicher Mahnung der fällige Teil des Teilnahmebeitrags nicht innerhalb von zwei Wochen bezahlt wird."

        pdf.move_down 3.mm
        text "8.3 Im Falle der Kündigung nach Ziff. 8.1 und 8.2 behält der rdp den Anspruch auf den Teilnahmebeitrag. Er muss sich jedoch den Wert ersparter Aufwendungen sowie die Vorteile anrechnen lassen, die aus einer anderen Verwendung nicht in Anspruch genommener Leistungen erlangt werden, einschließlich evtl. erlangter Erstattungen durch Leistungsträger. Die Geltendmachung von weiterem Schadensersatz bleibt vorbehalten; dies gilt insbesondere für Mehrkosten für die Rückbeförderung des Teilnehmers."

        pdf.move_down 3.mm
        text "8.4 Der rdp behält sich vor, in folgenden Fällen vom Vertrag zurückzutreten:"

        pdf.move_down 3.mm
        text "a) Absage des Jamborees durch den polnischen Veranstalter (Organising Committee for the 26th World Scout Jamboree, Za murami 2-10, 80-823 Gdansk, Republik Polen)"

        pdf.move_down 3.mm
        text "b) höhere Gewalt; hierzu zählen auch Einreise- bzw. Ausreisebeschränkungen, staatliche Anordnungen im Zusammenhang mit der Ausbreitung von ansteckenden Erkrankungen."

        pdf.move_down 3.mm
        text "c) sonstige Umstände, die eine sichere Teilnahme des Deutschen Kontingents am 26. World Scout Jamboree aus Sicht des rdp unmöglich machen."

        pdf.move_down 3.mm
        text "Im Falle des Rücktritts verliert der rdp den Anspruch auf den Teilnahmebeitrag. Er kann jedoch vom Teilnehmenden eine angemessene Entschädigung bis zur Höhe der ihm bis zum Rücktritt entstandenen Kosten und Aufwendungen (z.B. für bereits erworbene Bahntickets, bereits gezahlte Beiträge an die Veranstalter des Jamborees, usw.) verlangen."

        pdf.move_down 3.mm
        text "9. Schlussbestimmungen"

        pdf.move_down 3.mm
        text "9.1 Die Vertragsdurchführung unterliegt ausschließlich deutschem Recht."

        pdf.move_down 3.mm
        text "9.2 Änderungen des Vertrages bedürfen der Schriftform. Mündliche Nebenabreden sind nicht getroffen."

        pdf.move_down 3.mm
        text "9.3 Sollten einzelne Bestimmungen des Vertrages oder der vorliegenden Reisebedingungen unwirksam oder nichtig sein oder werden, so wird die Wirksamkeit des Vertrages und der übrigen Bedingungen hiervon nicht berührt. Die Parteien werden in einem solchen Fall unter Berücksichtigung des Gesetzes eine Vereinbarung treffen, die der unwirksamen oder nichtigen Klausel wirtschaftlich nahekommt. Das gleiche soll für den Fall gelten, dass im Vertrag eine Regelungslücke offenbar wird."

        pdf.start_new_page
        text "Hinweise zur Datenverarbeitung", size: 12

        pdf.move_down 3.mm
        text "Diese Datenschutzhinweise gelten für die Verarbeitung personenbezogener Daten der Teilnehmer*innen am 26. World Jamboree 2027 durch den rdp."

        pdf.move_down 3.mm
        text "1. Verantwortlicher der Datenverarbeitung", size: 10

        pdf.move_down 3.mm
        text "1.1 Verantwortlich für die Datenverarbeitung ist der Ring deutscher Pfadfinder*innenverbände e.V. (rdp), vertreten durch Sebastian Becker, Alexander Schmidt, Leah Albrecht, Susanne Rüber und Naima Hartit "
        text "Chausseestraße 128/129,"
        text "10115 Berlin,"
        text "Telefonnummer Büro: +49 30 288 7895 35,"
        text "E-Mail: info@rdp-pfadfinden.de."

        pdf.move_down 3.mm
        text "1.2 Der Datenschutzbeauftragte des rdp, Adriaan Wind, ist erreichbar unter datenschutz@rdp-bund.de oder schriftlich unter "
        text "Ring deutscher Pfadfinder*innenverbände e.V. (rdp)"
        text "Adriaan Wind"
        text "Chausseestraße 128/129,"
        text "10115 Berlin"

        pdf.move_down 3.mm
        text "2. Erhobene Daten, Zwecke und Rechtsgrundlage der Datenverarbeitung", size: 10

        pdf.move_down 3.mm
        text "2.1 Bei der Anmeldung zur Veranstaltung erfasst der rdp über das Anmeldeformular unter anmeldung.worldscoutjamboree.de personenbezogene Daten des Teilnehmers und ggf. dessen/deren Personensorgeberechtigten. Diese Daten sind erforderlich für die Vorbereitung und Durchführung der Veranstaltung. Ohne Offenlegung der Daten sind die Anmeldung und die Teilnahme nicht möglich. Rechtsgrundlage der Verarbeitung ist die Anbahnung und Erfüllung des Reisevertrages mit dem Teilnehmer, Art. 6 Abs. 1 lit. b DSGVO."

        pdf.move_down 3.mm
        text "2.2 Soweit gesundheitsbezogene Daten des Teilnehmers erfasst werden, erfolgt dies auch zum Schutz lebenswichtiger Interessen des Teilnehmers, Art. 6 Abs. 1 lit. d DSGVO."

        pdf.move_down 3.mm
        text "2.3 Mit Einwilligung des Teilnehmers werden Bild- und Tonaufnahmen angefertigt. Auf das gesonderte Dokument Fotohinweise und Einwilligung wird verwiesen."

        pdf.move_down 3.mm
        text "3. Empfänger bzw. Kategorien von Empfängern der personenbezogenen Daten", size: 10

        pdf.move_down 3.mm
        text "3.1 Einzelne Angehörige von Mitgliedsverbänden, die im Auftrag des rdp in Planung, Vorbereitung und Durchführung der Veranstaltung einbezogen sind (Mitglieder des Kontingentsteams im Besonderen Systemadministrator*innen, Unitmanager, Ärzt*innen, Tourenplanende, Logistiker*innen, und die jeweilig verantworlichen Unitleiter*innen) erhalten je nach Inhalt ihrer Tätigkeit Zugriff auf personenbezogene Daten der"
        text "Teilnehmer*innen, soweit dies für die Erfüllung der ihnen übertragenen Aufgaben erforderlich ist. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO. Mit den Empfängern ist eine Vertraulichkeitsvereinbarung abgeschlossen."

        pdf.move_down 3.mm
        text "3.2 Einzelne personenbezogene Daten werden an Unternehmen und Organisationen übertragen, deren Dienste der Veranstalter in Anspruch nimmt, um seine Pflichten aus dem Reisevertrag zu erfüllen (im Besonderen: Bund der Pfadfinderinnen und Pfadfinder e.V. (BdP) / Kesselhaken 23 34376 Immenhausen, Deutsche Pfadfinderschaft Sankt Georg / Martinstraße 2 in 41472 Neuss (Holzheim), Verband Christlicher Pfadfinderinnen und Pfadfinder / VCP Bundeszentrale Wichernweg 3 in 34121 Kassel). Hierzu zählen insbesondere Name, Anschrift, Geburtsdatum, Telefonnummern, Emailadresse, Mitgliedsnummer und Details zu den Reisedokumenten. Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO."

        pdf.move_down 3.mm
        text "3.3 Einzelne personenbezogene Daten werden an den Veranstalter des Jamboree (Organising Committee for the 26th World Scout Jamboree, Za murami 2-10, 80-823 Gdansk, Republik Polen) übermittelt. Dieser hat seinen Sitz in der Republik Polen und damit innerhalb des Geltungsbereiches der DSGVO. Der Veranstalter hat rechtliche und"
        text "technische Vorkehrungen getroffen, damit die Datensicherheit und der Datenschutz der personenbezogenen Daten der Teilnehmer*innen zu jeder Zeit gewährleistet ist. Nähere Auskünfte zu diesen Vorkehrungen erteilt der rdp auf Anfrage. Rechtsgrundlage der Übertragung ist Art. 6 Abs. 1 lit. b DSGVO."

        pdf.move_down 3.mm
        text "3.4 Auf die erhobenen Gesundheitsdaten haben folgende Personen Zugriff: Die jeweils verantwortlichen Unitleiter*innen und Unitmanager als verantwortliche Aufsichtspersonen; die Ärztinnen und Ärzte, soweit im Einzelfall eine medizinische Betreuung oder Behandlung des*der Teilnehmers*Teilnehmerin erforderlich wird; die Systemadministrator*innen des Deutschen Kontingents. Rechtsgrundlage sind Art. 6 Abs. 1 lit. b und d DSGVO. Mit den Empfängern ist eine Vertraulichkeitsvereinbarung abgeschlossen."

        pdf.move_down 3.mm
        text "3.5 Soweit gesundheitsbezogene Daten einzelner Teilnehmer*innen an den Veranstalter des Jamboree (Organising Committee for the 26th World Scout Jamboree, Za murami 2-10, 80-823 Gdansk, Republik Polen) übertragen werden, geschieht dies auf der Grundlage von Art. 6 Abs. 1 lit. b und d DSGVO."
        text "3.6. Wir setzen Hetzner Online GmbH, Industriestraße 25, 91710 Gunzenhausen als Auftragsverarbeiter ein."

        pdf.move_down 3.mm
        text "4. Speicherungs- und Löschfristen", size: 10

        pdf.move_down 3.mm
        text "4.1 Die erhobenen Daten werden gespeichert, solange ihre Kenntnis für die Vorbereitung, Durchführung und Nachbereitung des Jamboree erforderlich ist. Nach Ablauf der gesetzlichen Aufbewahrungsfristen werden die Daten gelöscht oder gesperrt."

        pdf.move_down 3.mm
        text "4.2 Für die Löschung von Bild- und Tonaufnahmen gelten die in der Fotoerlaubnis festgelegten Regelungen."

        pdf.move_down 3.mm
        text "5. Betroffenenrechte", size: 10

        pdf.move_down 3.mm
        text "Betroffene haben das Recht,"

        pdf.move_down 3.mm
        text "- gemäß Art. 15 DSGVO Auskunft über ihre vom rdp verarbeiteten personenbezogenen Daten zu verlangen. Insbesondere können sie Auskunft über die Verarbeitungszwecke, die Kategorie der personenbezogenen Daten, die Kategorien von Empfängern, gegenüber denen ihre Daten offengelegt wurden oder werden, die geplante Speicherdauer, das Bestehen eines Rechts auf Berichtigung, Löschung, Einschränkung der Verarbeitung oder Widerspruch, das Bestehen eines Beschwerderechts, die Herkunft ihrer Daten, sofern diese nicht bei dem rdp erhoben wurden, sowie über das Bestehen einer automatisierten Entscheidungsfindung einschließlich Profiling und ggf. aussagekräftigen Informationen zu deren Einzelheiten verlangen;"
        text "- gemäß Art. 16 DSGVO unverzüglich die Berichtigung unrichtiger oder Vervollständigung ihrer beim rdp gespeicherten personenbezogenen Daten zu verlangen;"
        text "- gemäß Art. 17 DSGVO die Löschung ihrer beim rdp gespeicherten personenbezogenen Daten zu verlangen, soweit sie nicht für die Zwecke der Vertragsdurchführung erforderlich sind oder die nicht die Verarbeitung zur Ausübung des Rechts auf freie Meinungsäußerung und Information, zur Erfüllung einer rechtlichen Verpflichtung, aus Gründen des öffentlichen Interesses oder zur Geltendmachung, Ausübung oder Verteidigung von Rechtsansprüchen erforderlich ist;"
        text "- gemäß Art. 18 DSGVO die Einschränkung der Verarbeitung ihrer personenbezogenen Daten zu verlangen, soweit (1) die Richtigkeit der Daten von ihnen bestritten wird, (2) die Verarbeitung unrechtmäßig ist, der Betroffene aber deren Löschung ablehnt, (3) der rdp die Daten nicht mehr benötigt, der*die Teilnehmer*in sie jedoch zur Geltendmachung, Ausübung oder Verteidigung von Rechtsansprüchen benötigt oder (4) der*die Teilnehmer*in gemäß Art. 21 DSGVO Widerspruch gegen die Verarbeitung eingelegt hat;"
        text "- gemäß Art. 20 DSGVO ihre personenbezogenen Daten, die sie dem rdp bereitgestellt haben, in einem strukturierten, gängigen und maschinenlesebaren Format zu erhalten oder die Übermittlung an einen anderen Verantwortlichen zu verlangen und"
        text "- gemäß Art. 77 DSGVO sich bei einer Aufsichtsbehörde zu beschweren."

        pdf.move_down 3.mm
        text "Stand dieser Hinweise: Juni 2025 (v1 vom 28.06.2025)"

        text ""
      end
    end
    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
  end
end
