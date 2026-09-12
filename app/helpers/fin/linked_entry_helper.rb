# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The "Person … · Verknüpfte Buchung …" line that every place showing a linked
# Beitragsbuchung renders: both account statements (the camt one and the Moss
# wallet) and the transaction / Moss-booking pages.
#
# How much of that line is rendered depends on what the viewer may see, and the
# entry's own label is the strict part: "[8398] <Beschreibung> (<Betrag>)" is
# one person's fee data, exactly like the entry page a link would lead to. It is
# therefore spelled out only for someone who may see BOTH the entry
# (`can?(:show, entry)`) and its person (`can?(:show, subject)`) -- asked
# through hitobito's assoc_link?, which also checks that a route exists.
# Everyone else gets the line without any link, and the entry by its bare id:
#
#   may:     Person: <a>Vorname Nachname</a> • Verknüpfte Buchung: <a>[8398] Retoure … (-303,85)</a>
#   may not: Person: Vorname Nachname       • Verknüpfte Buchung: #8398
#
# The name itself stays: the statement shows it from the bank data anyway
# (dbtr_name), it is what makes a row identifiable, and it is not what the rule
# protects. The case this is written for is the finance READ tier -- a
# Group::Extern::FinanceAuditor reaches every statement (:show on the finance
# models, doc/roles.md -> "Finance tiers") but holds neither AccountingEntry nor
# anything on people.
module Fin::LinkedEntryHelper
  # A transaction's or an entry's person: a link where the viewer may open the
  # person page, the plain (escaped) name otherwise.
  def fin_subject_link(subject)
    return "".html_safe if subject.blank?

    link_to_if(assoc_link?(subject), subject.short_full_name_with_nickname, subject)
  end

  # The Beitragsbuchung itself: its full label ("[8398] <Beschreibung>
  # (<Betrag>)") as a link for whoever may open it, the bare "#8398" as text for
  # everyone else.
  def fin_entry_link(entry)
    return link_to(entry.link_name, entry) if fin_entry_details_visible?(entry)

    "##{entry.id}"
  end

  # The rule: the entry AND its person. Both are the same person's fee data, and
  # either missing permission reduces the line to the bare id.
  def fin_entry_details_visible?(entry)
    subject = entry.subject
    assoc_link?(entry) && subject.present? && assoc_link?(subject)
  end
end
