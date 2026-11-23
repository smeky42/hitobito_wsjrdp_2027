# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One Moss expense (L2): its reading page (also the row detail the expenses
# table of a transaction's page lazy-loads) and its edit page (the comment).
# As Fin::MossBookingsController's booking pages.
class Fin::MossExpensesController < Fin::FinController
  include Wsjrdp::TableStateful
  include Fin::DetailPages

  # The prefix of the frame a direct visit gets (wsjrdp_detail_frame).
  FRAME_PREFIX = "mex"

  before_action :load_expense
  before_action :authorize_action

  # The bookings of the expense, as a table on its page (fin/moss_expenses/_detail),
  # all rows on one page and in their own order until a header is clicked;
  # date and kind, the same in every row, are left out by default.
  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "meb",
    columns: Fin::MossBookingsColumns.codec,
    cols: {default: Fin::MossBookingsColumns::PARENT_DEFAULT_KEYS},
    per_page: {default: :all}

  helper_method :expense_bookings_rows

  def expense_bookings_rows(expense)
    Fin::MossBookingsColumns.rows(wsjrdp_expandable_table_state(BOOKINGS_POLICY),
      MossBooking.joins(:moss_transaction).where(moss_expense_id: expense.id),
      natural_order: ->(source) { source.order(:sub_row_number) }, tiebreaker: "moss_bookings.id")
  end

  def show
    @ctx = detail_format_context
  end

  def edit
    authorize!(:update, @moss_expense)
    @ctx = Fin::AttrFormatContext.regular
  end

  def update
    authorize!(:update, @moss_expense)
    save_detail(@moss_expense, params.require(:moss_expense).permit(:comment),
      notice: "Moss Ausgabe #{@moss_expense.id} erfolgreich aktualisiert.")
  end

  private

  # The expense, and its transaction for the Moss sheet's kind tabs.
  def load_expense
    @moss_expense = MossExpense.includes(:moss_transaction, :bookings).find(params[:id])
    @transaction = @moss_expense.moss_transaction
  end

  def authorize_action
    authorize!(:show, @moss_expense)
  end
end
