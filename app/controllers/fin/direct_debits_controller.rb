# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Einzüge" tab of the Zahlungsverkehr area at /fin/payments/debits: every
# debit (pre-notification) of every order, with its collection entry and its
# returns. A debit's page (/fin/payments/debits/:id) -- also the row's lazy
# detail -- shows its payment data (fin/direct_debits/_detail); its edit page
# (/fin/payments/debits/:id/edit) changes what the pre-notification's own page
# would (Fin::DebitEditing), for whoever may :update pre-notifications (the
# finance tier and up) -- the manage tier (:admin_finance) also the status,
# and the mandate reference of a debit only announced.
# Person-level payment data: :log on WsjrdpFinAccount, as the Personen tab of
# Beiträge. A debit's pages are shared with its page under its person
# (Fin::DebitPages). See doc/fin/payments.md.
class Fin::DirectDebitsController < Fin::FinController
  include Wsjrdp::TableStateful
  include Fin::DebitPages

  before_action :authorize_action

  TIEBREAKER = "wsjrdp_direct_debit_pre_notifications.id DESC"

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::DirectDebitsColumns::COLUMNS.codec,
    sort: {hidden: [["collection_date", "desc"], ["person", "asc"]]},
    cols: {default: Fin::DirectDebitsColumns::COLUMNS.default_keys},
    per_page: {default: 100},
    filter: {schema: Fin::DirectDebitsFilterSchema, presets: Fin::DirectDebitsFilterSchema::PRESETS}

  helper_method :direct_debits, :direct_debit_totals

  def index
  end

  def show
    @debit = find_debit
    @ctx = detail_format_context
  end

  def edit
    @debit = find_debit
    authorize!(:update, @debit)
    @ctx = Fin::AttrFormatContext.regular
  end

  def update
    @debit = find_debit
    authorize!(:update, @debit)
    save_debit(@debit)
  end

  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: direct_debits_path)
  end

  private

  def authorize_action
    authorize!(:log, WsjrdpFinAccount)
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def debit_page_path(debit, **) = direct_debit_path(debit, **)

  def edit_debit_page_path(debit, **) = edit_direct_debit_path(debit, **)

  # The record's own page, or a list row's detail (a turbo frame) at the
  # nesting level the list put into the frame's URL (doc/fin/detail_partials.md).
  def detail_format_context
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: table_state.level, lazy: true))
  end

  def filtered_debits
    @filtered_debits ||= table_state.filter.scope(Fin::PaymentQueries.debits)
  end

  def direct_debits
    @direct_debits ||= Wsjrdp::ExpandableTableRows.new(table_state, filtered_debits,
      sort: Fin::DirectDebitsColumns::COLUMNS.sort_expressions, tiebreaker: TIEBREAKER, preload: [{subject: [{roles: :group}, {roles_with_ended_readable: :group}, :groups_with_roles_ended_readable]}])
  end

  def direct_debit_totals
    @direct_debit_totals ||= Fin::PaymentQueries.debit_totals(filtered_debits)
  end
end
