# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The SEPA return reasons (ISO 20022 ExternalReturnReason1Code) a return
# debit names, with the German wording the banks use -- the tooltip of a
# reason code in the Zahlungsverkehr lists (doc/fin/payments.md). A code not
# listed shows as it is.
module Fin::ReturnReasons
  LABELS = {
    "AC01" => "Kontonummer fehlerhaft (IBAN ungültig)",
    "AC04" => "Konto erloschen",
    "AC06" => "Konto gesperrt",
    "AC13" => "Debitor ist Verbraucher, Lastschrift aber Firmenlastschrift",
    "AG01" => "Lastschrift auf diesem Konto nicht erlaubt",
    "AG02" => "Ungültiger Bankcode",
    "AM04" => "Deckung unzureichend",
    "AM05" => "Doppelte Einreichung",
    "BE05" => "Gläubiger unbekannt",
    "CNOR" => "Bank des Gläubigers nicht erreichbar",
    "DNOR" => "Bank des Zahlers nicht erreichbar",
    "FF01" => "Formatfehler",
    "MD01" => "Kein gültiges Mandat",
    "MD02" => "Mandatsdaten fehlen oder sind fehlerhaft",
    "MD06" => "Widerspruch durch den Zahler (Rückgabe innerhalb von 8 Wochen)",
    "MD07" => "Kontoinhaber verstorben",
    "MS02" => "Ablehnung durch den Zahler, ohne Angabe von Gründen",
    "MS03" => "Ablehnung durch die Bank, ohne Angabe von Gründen",
    "RC01" => "BIC fehlerhaft",
    "RR01" => "Angaben zum Zahler fehlen (regulatorisch)",
    "RR02" => "Name oder Adresse des Zahlers fehlt (regulatorisch)",
    "RR03" => "Name oder Adresse des Gläubigers fehlt (regulatorisch)",
    "RR04" => "Regulatorische Gründe",
    "SL01" => "Besondere Dienstleistung der Bank des Zahlers"
  }.freeze

  module_function

  # The wording of a code, nil for one not listed.
  def label(code) = LABELS[code.to_s.strip.upcase]

  # The codes as filter options: those that occur, with their wording.
  def options(codes) = codes.compact.uniq.sort.map { |code| [code, [code, label(code)].compact.join(" – ")] }
end
