# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Reduktionen" tab of the Beiträge area at /fin/fee_reductions: every person
# with an active total fee reduction (wsjrdp_total_fee_reduction <> 0) or a
# planned one, each row opening into the "Beitragshöhe" view of that person
# (person/fee/_fee_reduction in its finance-area form). Changes are made on the
# person's Beitrag page.
class Fin::FeeReductionsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::FeeReductionsColumns::COLUMNS.codec,
    # Oldest activation first, as a hidden order under whatever the user sorts.
    sort: {hidden: [["activated_at", "asc"]]},
    cols: {default: Fin::FeeReductionsColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::FeeReductionsFilterSchema, presets: Fin::FeeReductionsFilterSchema::PRESETS}

  helper_method :fee_reductions

  def index
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: fin_fee_reductions_path)
  end

  private

  # Person-level fee data: the audit tier and up, as on the Personen tab
  # (Fin::WsjrdpFinPersonFeesController) -- the read tier does not see it.
  def authorize_action
    authorize!(:log, WsjrdpFinAccount)
  end

  def fee_reductions
    @fee_reductions ||= Wsjrdp::ExpandableTableRows.new(
      table_state,
      Fin::FeeReductionRow.for(table_state.filter.scope(people_with_reduction).includes(:roles, :primary_group)),
      sort: Fin::FeeReductionsColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(row) { row.id }
    )
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # An active reduction, or a planned one. The planned values sit in
  # additional_info; jsonb_exists, as `?` would read as a bind placeholder.
  def people_with_reduction
    Person.where.not(wsjrdp_total_fee_reduction: 0)
      .or(Person.where("jsonb_exists(people.additional_info, 'planned_total_fee_reduction')"))
  end
end
