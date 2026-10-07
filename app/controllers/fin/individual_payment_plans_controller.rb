# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Individuelle Ratenpläne" tab of the Beiträge area at
# /fin/individual_payment_plans: every person with an active individual
# installment plan or a planned one (Fin::IndividualPaymentPlanRow), the
# planned plan as a sub-row under the active one. Plans are maintained on the
# person's status page.
class Fin::IndividualPaymentPlansController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::IndividualPaymentPlansColumns::COLUMNS.codec,
    # Newest activation first, as a hidden order under whatever the user sorts.
    sort: {hidden: [["activated_at", "desc"]]},
    cols: {default: Fin::IndividualPaymentPlansColumns::COLUMNS.default_keys},
    per_page: {default: 100},
    filter: {schema: Fin::IndividualPaymentPlansFilterSchema,
             presets: Fin::IndividualPaymentPlansFilterSchema::PRESETS}

  helper_method :individual_payment_plans, :strip_length

  def index
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: fin_individual_payment_plans_path)
  end

  private

  # Person-level fee data: the audit tier and up, as on the Personen tab
  # (Fin::WsjrdpFinPersonFeesController) -- the read tier does not see it.
  def authorize_action
    authorize!(:log, WsjrdpFinAccount)
  end

  def individual_payment_plans
    @individual_payment_plans ||= Wsjrdp::ExpandableTableRows.new(
      table_state,
      listed_rows,
      sort: Fin::IndividualPaymentPlansColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(row) { row.id }
    )
  end

  # Every row, unfiltered: the strip's column is as wide as the longest strip
  # of them all (#strip_length), so it does not change with the filter.
  def all_rows
    @all_rows ||= Fin::IndividualPaymentPlanRow.for(
      Fin::IndividualPaymentPlanRow.people_with_plan
        .includes(:roles, :primary_group, :accounting_entries, :direct_debit_pre_notifications)
    )
  end

  # The rows the filter leaves (the filter is SQL on people).
  def listed_rows
    ids = table_state.filter.scope(Fin::IndividualPaymentPlanRow.people_with_plan).pluck(:id).to_set
    all_rows.select { |row| ids.include?(row.id) }
  end

  def strip_length
    @strip_length ||= all_rows.filter_map(&:strip_length).max || Fin::ListedPaymentPlan::STRIP_LENGTH
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)
end
