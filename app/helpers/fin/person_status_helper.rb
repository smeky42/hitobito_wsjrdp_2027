# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A person's registration status and participation contract as the lists of
# the Beiträge area show them (the Reduktionen, the Individuelle Ratenpläne):
# in a word, coloured where it matters, the full label (Settings.status,
# Settings.contract_status) as the tooltip. The colours:
# fin/_person_status_styles.
module Fin::PersonStatusHelper
  # The cell of the column "contract" or "status" (Fin::PersonStatusColumns):
  # each names the other where that one is hidden (+visible_keys+, the
  # columns shown).
  def fin_person_cell(key, person, visible_keys)
    if key == "contract"
      fin_person_contract(person, status: visible_keys.exclude?("status"))
    else
      fin_person_status(person, contract: visible_keys.exclude?("contract"))
    end
  end

  # The status in colour where it matters: confirmed green, a noted
  # deregistration orange, a deregistration red.
  STATUS_CLASSES = {"confirmed" => "fin-status-confirmed",
                    "deregistration_noted" => "fin-status-noted",
                    "deregistered" => "fin-status-deregistered"}.freeze

  STATUS_WORDS = {"registered" => "registriert", "printed" => "gedruckt", "upload" => "hochgeladen",
                  "in_review" => "in Prüfung", "reviewed" => "geprüft", "confirmed" => "bestätigt",
                  "deregistration_noted" => "Abmeldung", "deregistered" => "abgemeldet"}.freeze

  # With `contract: true` (the contract's column hidden) the contract follows
  # the status, small and muted, where the two do not go together
  # (#fin_status_and_contract_match?); the tooltip names both.
  def fin_person_status(person, contract: false)
    status = person.status.to_s
    word = tag.span(STATUS_WORDS.fetch(status, status), class: STATUS_CLASSES[status])
    lines = fin_person_status_lines(person)
    return wsjrdp_tip(word, lines: lines) unless contract

    other = fin_person_contract_word(person) unless fin_status_and_contract_match?(person)
    wsjrdp_tip(fin_person_word_pair(word, other), lines: lines + fin_person_contract_lines(person))
  end

  # The contract in colour as it matters for the payments: in force green
  # (collected), waiting for its replacement orange, ended red, none plain.
  CONTRACT_CLASSES = {"confirmed" => "fin-status-confirmed",
                      "replacement_pending" => "fin-status-noted",
                      "ended" => "fin-status-deregistered"}.freeze

  CONTRACT_WORDS = {"none" => "keiner", "confirmed" => "in Kraft", "replacement_pending" => "ausstehend",
                    "ended" => "beendet"}.freeze

  # The pairs of contract and status that go together in the course of a
  # registration: no contract during the registration, the contract in force
  # with the confirmation, ended with the deregistration. Every other pair --
  # a contract waiting for its replacement always, a contract in force with a
  # noted deregistration -- is worth a second word where only one of the two
  # columns is shown.
  MATCHING_STATUSES = {"none" => %w[registered printed upload in_review reviewed],
                       "confirmed" => %w[confirmed],
                       "ended" => %w[deregistered]}.freeze

  def fin_status_and_contract_match?(person)
    MATCHING_STATUSES.fetch(person.contract_status.to_s, []).include?(person.status.to_s)
  end

  # With `status: true` (the status' column hidden) the status follows the
  # contract, small and muted, where the two do not go together; the tooltip
  # names both.
  def fin_person_contract(person, status: false)
    word = tag.span(fin_person_contract_word(person), class: CONTRACT_CLASSES[person.contract_status.to_s])
    lines = fin_person_contract_lines(person)
    return wsjrdp_tip(word, lines: lines) unless status

    other = STATUS_WORDS.fetch(person.status.to_s, person.status.to_s) unless fin_status_and_contract_match?(person)
    wsjrdp_tip(fin_person_word_pair(word, other), lines: fin_person_status_lines(person) + lines)
  end

  private

  def fin_person_contract_word(person) = CONTRACT_WORDS.fetch(person.contract_status.to_s, person.contract_status.to_s)

  def fin_person_status_lines(person)
    status = person.status.to_s
    [["Status", Settings.status[status].presence || status]]
  end

  def fin_person_contract_lines(person)
    status = person.contract_status.to_s
    lines = [["Vertrag", Settings.contract_status[status].presence || status]]
    lines << ["bestätigt", l(person.contract_confirmed_at, format: "%d.%m.%Y")] if person.contract_confirmed_at
    lines << ["beendet", l(person.contract_ended_at, format: "%d.%m.%Y")] if person.contract_ended_at
    lines
  end

  # The shown word, then the other one small, muted and light.
  def fin_person_word_pair(word, other)
    return word if other.nil?

    safe_join([word, " ", tag.span(other, class: "fin-status-other small muted fw-light")])
  end
end
