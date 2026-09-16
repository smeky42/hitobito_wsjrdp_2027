# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Gruppen-Finanzzugriff page (Fin::FinanceGroupsController).
module Fin::FinanceGroupsHelper
  # Which of the two finance actions the person already holds on the group
  # WITHOUT the entry -- through a role, a layer or a finance tier. The page
  # marks such a row, because removing the entry would change nothing there.
  #
  # Answered with a PROBE: a fresh copy of the person with finance_group_ids
  # cleared, and an ability built for it. The copy is never saved, and it is a
  # copy precisely so the cleared field cannot travel back into the row the
  # page renders.
  # Called once per row, each row being a different (person, group) pair, so
  # there is nothing to memoize.
  def finance_by_role(person, group)
    return [] if group.nil?

    probe = Person.find(person.id)
    probe.finance_group_ids = nil
    ability = Ability.new(probe)
    tokens = []
    tokens << "show" if ability.can?(:show_finance, group)
    tokens << "update" if ability.can?(:update_finance, group)
    tokens
  end

  # The label of an access level ("show", "show,update"), or nil for tokens the
  # page has no level for.
  def finance_group_level_label(tokens)
    key = Array(tokens).join(",")
    t("fin.finance_groups.levels.#{key}", default: nil) if Fin::FinanceGroupsController::LEVELS.include?(key)
  end

  # The person's roles the field works for, as one string ("Unit Manager").
  def finance_group_role_labels(person)
    person.finance_group_candidate_roles.map { |role| role.to_s(:short) }.join(", ")
  end

  # The name the page calls a group by. An id that resolves to no group keeps
  # its number, so a stale entry stays recognisable and removable.
  def finance_group_name(entry)
    entry.group ? entry.group.name : "##{entry.group_id}"
  end

  # The labels of the two access levels, keyed by the stored token list. Handed
  # to the page's script, which writes a pending level change as "old -> new".
  def finance_group_level_labels
    Fin::FinanceGroupsController::LEVELS
      .index_with { |level| t("fin.finance_groups.levels.#{level}") }
  end

  # The pending summary as a TEMPLATE for the page's script, the three counts
  # still their %{...} placeholders. I18n always interpolates, so each
  # placeholder is handed back to it as its own value.
  def finance_group_pending_summary_template
    t("fin.finance_groups.pending.summary",
      added: "%{added}", changed: "%{changed}", removed: "%{removed}")
  end

  # Person and role in one label, for the select of the add form.
  def finance_group_candidate_label(person)
    roles = finance_group_role_labels(person)
    roles.present? ? "#{person} (#{roles})" : person.to_s
  end
end
