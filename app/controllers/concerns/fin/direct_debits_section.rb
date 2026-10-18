# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Einzüge section of a page in Zahlungsverkehr -- an order's, a Sammler's
# (doc/fin/payments.md): the debits table (fin/direct_debits/_table) over the
# debits the host picks (#section_debits_scope), filtered on its own (DEBITS
# prefix "d"), without the order column. Person-level payment data: the
# section shows with :log on WsjrdpFinAccount only (#section_debits?), and its
# filter's apply action asks for it.
module Fin::DirectDebitsSection
  extend ActiveSupport::Concern

  included do
    include Wsjrdp::TableStateful

    const_set(:DEBITS_POLICY, wsjrdp_expandable_table_policy(prefix: "d",
      columns: Fin::DirectDebitsColumns::COLUMNS.codec,
      sort: {hidden: [["person", "asc"]]},
      cols: {default: Fin::DirectDebitsColumns::COLUMNS.default_keys - %w[order], exclude: %w[order]},
      per_page: {default: 100},
      filter: {schema: Fin::DirectDebitsFilterSchema, presets: Fin::DirectDebitsFilterSchema::PRESETS,
               exclude: %i[order]}))

    helper_method :section_debits, :section_debit_totals, :section_debits?
  end

  # Apply target of the section's filter: back to the page (the host's
  # #section_path).
  def apply_debits
    authorize!(:log, WsjrdpFinAccount)
    wsjrdp_apply_table_filter(debits_table_state, redirect_to: section_path)
  end

  private

  def debits_table_state = wsjrdp_expandable_table_state(self.class::DEBITS_POLICY)

  def section_debits?
    can?(:log, WsjrdpFinAccount)
  end

  def filtered_section_debits
    @filtered_section_debits ||= debits_table_state.filter.scope(section_debits_scope)
  end

  def section_debits
    @section_debits ||= Wsjrdp::ExpandableTableRows.new(debits_table_state, filtered_section_debits,
      sort: Fin::DirectDebitsColumns::COLUMNS.sort_expressions,
      tiebreaker: Fin::DirectDebitsController::TIEBREAKER, preload: [{subject: [{roles: :group}, {roles_with_ended_readable: :group}, :groups_with_roles_ended_readable]}])
  end

  def section_debit_totals
    @section_debit_totals ||= Fin::PaymentQueries.debit_totals(filtered_section_debits)
  end
end
