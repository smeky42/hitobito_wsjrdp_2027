# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Zahlungscodes", a tab of the Verwaltung area
# (/fin/admin/payment_references): the payment references
# (WsjrdpPaymentReference) as an expandable table, the stock of available ones,
# and making new ones for the stock. A code's page
# (/fin/admin/payment_references/:id) shows the code with the payment notices
# using it; it is also the lazy detail of the code's row, and its comment is
# edited inline there. The finance write tier and up, and admins, see the codes
# and edit the comment (:show / :update on WsjrdpPaymentReference); making
# codes for the stock is :configure_finance, admins and the finance manage
# tier.
class Fin::PaymentReferencesController < Fin::FinController
  include Wsjrdp::TableStateful

  # The most references one request makes.
  MAX_GENERATE = 5000

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::PaymentReferencesColumns::COLUMNS.codec,
    # Newest first, as a hidden order under whatever the user sorts.
    sort: {hidden: [["created_at", "desc"]]},
    cols: {default: Fin::PaymentReferencesColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::PaymentReferencesFilterSchema,
             presets: Fin::PaymentReferencesFilterSchema::PRESETS},
    pane: {default: 0}

  before_action :authorize_action

  helper_method :payment_references, :counts, :people_by_id

  def index
  end

  # A code with its notices: the page, or the lazy detail of the code's row.
  def show
    @reference = WsjrdpPaymentReference.find(params[:id])
    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # Saves the comment, the one editable field, and answers with the code's
  # page -- inside a row's detail that is the frame again (a form in a lazy
  # detail redirects to the detail, doc/wsjrdp/expandable_table.md).
  def update
    @reference = WsjrdpPaymentReference.find(params[:id])
    authorize!(:update, @reference)
    @reference.update!(comment: params.require(:wsjrdp_payment_reference).fetch(:comment, "").to_s)
    redirect_to fin_admin_payment_reference_path(@reference), notice: t("fin.payment_references.comment_saved")
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: fin_admin_payment_references_path)
  end

  # Makes count new available references; without a count as many as the
  # pool lacks.
  def generate
    count = requested_count
    return redirect_with_alert(t("fin.payment_references.invalid_count", max: MAX_GENERATE)) if count.nil?
    return redirect_to(fin_admin_payment_references_path, notice: t("fin.payment_references.pool_full")) if count.zero?

    WsjrdpPaymentReference.generate!(count)
    redirect_to fin_admin_payment_references_path, notice: t("fin.payment_references.generated", count: count)
  end

  private

  def authorize_action
    if action_name == "generate"
      authorize!(:configure_finance, Group)
    else
      authorize!(:show, WsjrdpPaymentReference)
    end
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # THE table: every reference the filter leaves, with the number of notices
  # using it, ordered and paged by the table's state; the id breaks ties, the
  # newest first.
  def payment_references
    @payment_references ||= Wsjrdp::ExpandableTableRows.new(table_state,
      table_state.filter.scope(WsjrdpPaymentReference.select("wsjrdp_payment_references.*",
        "#{Fin::PaymentReferencesColumns::NOTICE_COUNT_SQL} AS notice_count")),
      sort: Fin::PaymentReferencesColumns::COLUMNS.sort_expressions,
      tiebreaker: "wsjrdp_payment_references.id DESC")
  end

  def requested_count
    return WsjrdpPaymentReference.missing_for_pool if params[:count].blank?

    count = Integer(params[:count], exception: false)
    count if count&.between?(1, MAX_GENERATE)
  end

  def redirect_with_alert(message)
    redirect_to fin_admin_payment_references_path, alert: message
  end

  def counts
    @counts ||= WsjrdpPaymentReference.group(:status).count
  end

  # The people the shown code's notices are for, by id.
  def people_by_id
    @people_by_id ||= Person.where(id: @reference.payment_notices.where(subject_type: "Person").select(:subject_id))
      .index_by(&:id)
  end
end
