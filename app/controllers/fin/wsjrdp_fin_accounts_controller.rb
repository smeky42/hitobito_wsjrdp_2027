# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The statement of ONE finance account (/fin/acc/:id) -- and the account's own
# form below it. The page serves TWO kinds of account, and #show branches on
# exactly one thing (WsjrdpFinAccount#transactions branches on the same marker):
#
#   * a BANK account (transaction_type "WsjrdpCamtTransaction"): the plain
#     camt statement it has always been, every row rendered at once
#     (#ordered_transactions, sorted in Ruby);
#   * the MOSS WALLET (transaction_type "MossBalanceMovement"): the expandable
#     table below -- filterable, sortable, paged, with one quick-select button
#     per Moss kind. Its rows are MossBookings (L3), the grain the wallet
#     statement, the DATEV export and the booking detail page all speak.
class Fin::WsjrdpFinAccountsController < Fin::FinController
  include WsjrdpFormHelper
  include Fin::AccessHelper
  include WsjrdpNumberHelper
  include Wsjrdp::TableStateful

  decorates :person

  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  before_action :authorize_action
  before_action :check_fin_params_and_cookies

  helper_method :can_fin_admin?
  helper_method :fin_account, :ordered_transactions
  helper_method :moss_wallet?, :wallet_bookings
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :fin_account_path
  helper_method :link_subject_path
  helper_method :disallow_link_subject_path

  # The wallet statement's table (doc/wsjrdp/expandable_table.md). Declared on
  # the controller although only ONE of its accounts renders it -- a policy is a
  # class-level declaration by construction, and resolving it is what costs, not
  # declaring it (#show resolves it on the wallet branch only).
  #
  # The FILTER keeps the kit's default `:url` policy (D6), unlike the Buchungen
  # and Moss lists: this page is reached from an account, from a person's
  # finance page and from a DATEV booking, and each of those arrivals means
  # "show me this wallet", not "show me the last thing I filtered". A remembered
  # filter would silently hide rows from someone who followed a link -- and the
  # four kind buttons make re-filtering one click anyway.
  #
  # The store_key carries the account id, so the REMEMBERED half (sort, columns,
  # page size, page) is per account: two accounts are two statements, not two
  # views of one. params[:id] is nil outside a real request (the smoke spec
  # spec/controllers/fin/table_policies_spec.rb resolves every policy with a bare
  # TestRequest), which simply yields one more key -- nothing here needs an id to
  # resolve.
  WALLET_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::MossWalletColumns.codec,
    sort: {default: [["value_date", "desc"]]},
    cols: {default: Fin::MossWalletColumns.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::MossWalletFilterSchema, presets: -> { wallet_presets }},
    pane: {default: 1},
    store_key: -> { "#{controller_path}##{action_name}:#{params[:id]}" }

  def index
    authorize!(:show, WsjrdpFinAccount)
    @wsjrdp_fin_accounts = WsjrdpFinAccount.all
  end

  def show
    authorize!(:show, fin_account)
    @wsjrdp_fin_account ||= fin_account
    # Only the camt branch pre-sorts every row of the account in Ruby; the
    # wallet's rows come from its table state (wallet_bookings), one page at a
    # time, and are resolved by the view that actually renders them.
    @ordered_transactions ||= ordered_transactions unless moss_wallet?
    render :show
  end

  def update
    authorize!(:edit, fin_account)
    authorize!(:fin_admin, fin_account)
    @wsjrdp_fin_account ||= fin_account
    @wsjrdp_fin_account.attributes = permitted_params
    if @wsjrdp_fin_account.save
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  # PRG target of the wallet's CNF filter builder; lands back on this account.
  def apply
    authorize!(:show, fin_account)
    wsjrdp_apply_table_filter(wallet_table_state, redirect_to: wsjrdp_fin_account_path(fin_account))
  end

  def fin_account
    @wsjrdp_fin_account ||= WsjrdpFinAccount.find(params[:id])
  end

  # Is this account the Moss wallet? The stored discriminator's value is still
  # the pre-unification class name, so it is treated as an opaque marker -- the
  # same test WsjrdpFinAccount#transactions makes.
  def moss_wallet? = fin_account.transaction_type == "MossBalanceMovement"

  def ordered_transactions
    @ordered_transactions ||= fin_account.transactions.sort_by { |t| [t.value_date, t.id] }.reverse
  end

  # The resolved state of the wallet statement's table.
  def wallet_table_state = wsjrdp_expandable_table_state(WALLET_POLICY)

  # The wallet statement: the filtered, sorted, paged bookings of this account.
  # Everything the row cells reach for is preloaded -- the payment (kind, party,
  # currency), the expense (a reimbursement's own name and text), the person a
  # booking is assigned to and the linked contribution bookings with their
  # person. (An invoice's creditor name comes from the page's account-name map,
  # not from the polymorphic supplier association -- see
  # Fin::MossWalletHelper#moss_wallet_supplier.)
  def wallet_bookings
    @wallet_bookings ||= Wsjrdp::ExpandableTableRows.new(wallet_table_state,
      wallet_table_state.filter.scope(wallet_base),
      sort: Fin::MossWalletColumns.sort_expressions,
      preload: [:moss_transaction, :moss_expense, :contribution_subject, {accounting_entries: :subject}],
      tiebreaker: "moss_bookings.id DESC")
  end

  def can_fin_admin?
    can?(:fin_admin, fin_account) && param_is_true(cookies, :fin_admin)
  end

  private

  # THE unfiltered row set of the wallet statement: every booking whose payment
  # hangs on this account.
  #
  # Deliberately NOT fin_account.moss_bookings, which the assignment named: that
  # has_many-through joins moss_transactions itself, and the filter schema's own
  # base (MossBooking.joins(:moss_transaction)) joins it a second time under an
  # alias -- two INNER JOINs of the same table where one does. The explicit join
  # below merges with the schema's into exactly one (verified: both forms return
  # the same rows).
  def wallet_base
    MossBooking.joins(:moss_transaction).where(moss_transactions: {fin_account_id: fin_account.id})
  end

  # The "Schnellauswahl" above the wallet's filter: one button per Moss kind, in
  # the kinds' own order, each carrying the kind's icon and colour class so the
  # bar reads like the chips in the rows (doc/wsjrdp/expandable_table.md,
  # "Presets").
  #
  # The four are one GROUP, not four presets of their own: the kinds are
  # alternatives of the same question, so they share ONE slot `kind in (…)` and
  # two pressed buttons widen the statement to both kinds instead of ANDing two
  # slots into nothing. The words are the chip words of the rows
  # (fin.moss.kind_chips), so the bar and the "Art" cell read alike; the key is
  # the kind's slug, the value the STI type the filter compares.
  #
  # A LAMBDA in the policy, not a constant: the labels are I18n and must not be
  # looked up while the class loads.
  def wallet_presets
    [Fin::MossKinds.preset_group]
  end

  def authorize_action
    authorize!(:show, WsjrdpFinAccount)
  end

  def return_url
    return_url_or_fallback url_for(fin_account)
  end

  def cancel_url
    return_url
  end

  def fin_account_path(entry = nil)
    url_for(entry.nil? ? fin_account : entry)
  end

  def link_subject_path(tx, subject)
    "#{url_for(tx)}/link_subject/#{subject.id}/#{subject.class.name}"
  end

  def disallow_link_subject_path(tx, subject)
    "#{url_for(tx)}/disallow_link_subject/#{subject.id}/#{subject.class.name}"
  end

  def model_params
    params.require(:wsjrdp_fin_account)
  end

  def permitted_attrs
    [:short_name, :description]
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end
end
