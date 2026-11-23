# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The statement of ONE finance account (/fin/acc/:id), under the account's head
# line with its detail; its form is the edit page. The page serves TWO kinds of
# account, and #show branches on
# exactly one thing (WsjrdpFinAccount#transactions branches on the same marker):
#
#   * a BANK account (transaction_type "WsjrdpCamtTransaction"): the plain
#     camt statement it has always been, every row rendered at once
#     (#ordered_transactions, sorted in Ruby);
#   * the MOSS WALLET (transaction_type "MossBalanceMovement"): the Moss
#     transactions table of the Transaktionen tab (Fin::MossTransactionsTable,
#     fin/moss_transactions/_table), narrowed to this account.
class Fin::WsjrdpFinAccountsController < Fin::FinController
  include WsjrdpFormHelper
  include WsjrdpNumberHelper
  include Wsjrdp::TableStateful
  include Fin::MossTransactionsTable

  decorates :person

  TOP_UP_ATTRS = [:top_up_recipient_name, :top_up_iban, :top_up_bic, :top_up_purpose].freeze

  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  before_action :authorize_action

  helper_method :fin_account, :ordered_transactions
  helper_method :moss_wallet?
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :fin_account_path

  # The wallet's transactions table (doc/wsjrdp/expandable_table.md), with the
  # columns, the filter and the kind choice of the Transaktionen tab. Declared
  # on the controller although only ONE of its accounts renders it -- a policy
  # is a class-level declaration by construction, and resolving it is what
  # costs, not declaring it (#show resolves it on the wallet branch only).
  #
  # The FILTER and the kind choice keep the kit's default `:url` policy (D6),
  # unlike the Moss lists: this page is reached from an account, from a person's
  # finance page and from a DATEV booking, and each of those arrivals means
  # "show me this wallet", not "show me the last thing I filtered". A remembered
  # filter would silently hide rows from someone who followed a link -- and the
  # kind choice makes re-filtering one click anyway.
  #
  # The store_key carries the account id, so the REMEMBERED half (sort, columns,
  # page size, page) is per account: two accounts are two statements, not two
  # views of one. params[:id] is nil outside a real request (the smoke spec
  # spec/controllers/fin/table_policies_spec.rb resolves every policy with a bare
  # TestRequest), which simply yields one more key -- nothing here needs an id to
  # resolve.
  WALLET_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::MossTransactionsColumns.codec,
    sort: {hidden: [["booking_date", "desc"]]},
    cols: {default: Fin::MossTransactionsColumns.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::MossTransactionsFilterSchema, fixed_groups: -> { [Fin::MossKinds.fixed_group] }},
    pane: {default: 1},
    store_key: -> { "#{controller_path}##{action_name}:#{params[:id]}" }

  # The account list of the Übersicht: every account, a row opening the
  # account's detail (#show answering the row's frame). Without a sort of the
  # user's the list keeps the display order of the account tabs. Its own
  # prefix: the controller declares the wallet's table with the empty one.
  ACCOUNTS_POLICY = wsjrdp_expandable_table_policy prefix: "a",
    columns: Fin::FinAccountsColumns::COLUMNS.codec,
    cols: {default: Fin::FinAccountsColumns::COLUMNS.default_keys},
    per_page: {default: :all}

  # The id prefix of the frame the detail stands in on the account's own page.
  # The list's rows ask with theirs ("bkframe-acc-<id>"), and a save tells the
  # two apart by it (#redirect_after_save).
  PAGE_FRAME_PREFIX = "accpage"

  helper_method :accounts, :detail_frame_on_page?, :detail_format_context

  def index
    authorize!(:show, WsjrdpFinAccount)
    @wsjrdp_fin_accounts = WsjrdpFinAccount.display_order
  end

  # The account's page -- or, for a frame request, its detail alone: the row of
  # the list asks for it, and so does "Abbrechen" in the page's own frame.
  def show
    authorize!(:show, fin_account)
    @wsjrdp_fin_account ||= fin_account
    return render(:detail_frame) if turbo_frame_request?

    # Only the camt branch pre-sorts every row of the account in Ruby; the
    # wallet's rows come from its table state (transactions), one page at a
    # time, and are resolved by the view that actually renders them.
    @ordered_transactions ||= ordered_transactions unless moss_wallet?
    render :show
  end

  def accounts_table_state = wsjrdp_expandable_table_state(ACCOUNTS_POLICY)

  # THE account list, with each account's balance as `balance_eur` for the cell,
  # the footer and the sort.
  def accounts
    @accounts ||= Wsjrdp::ExpandableTableRows.new(accounts_table_state,
      WsjrdpFinAccount.select("wsjrdp_fin_accounts.*", "#{Fin::FinAccountsColumns::BALANCE_SQL} AS balance_eur"),
      sort: Fin::FinAccountsColumns::COLUMNS.sort_expressions,
      natural_order: ->(source) { source.display_order },
      tiebreaker: "wsjrdp_fin_accounts.id")
  end

  # Is this request the detail's frame on the account's own page (as opposed to
  # a row of the list)?
  def detail_frame_on_page?
    turbo_frame_request_id == helpers.wsjrdp_detail_frame_id(PAGE_FRAME_PREFIX, fin_account.id)
  end

  # WHERE the detail renders (Fin::AttrFormatContext): the account's page, or a
  # row's pane of the list.
  def detail_format_context
    if !turbo_frame_request? || detail_frame_on_page?
      Fin::AttrFormatContext.regular
    else
      Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: 1, lazy: true))
    end
  end

  # The EDIT PAGE of one account; #show is the reading page it is reached from
  # and comes back to. Authorized on the record, the way #update is.
  def edit
    authorize!(:update, fin_account)
    @wsjrdp_fin_account ||= fin_account
  end

  def update
    authorize!(:update, fin_account)
    @wsjrdp_fin_account ||= fin_account
    @wsjrdp_fin_account.attributes = permitted_params
    if @wsjrdp_fin_account.save
      redirect_after_save
    else
      render :edit, status: :bad_request
    end
  end

  # PRG target of the wallet's CNF filter builder; lands back on this account.
  def apply
    authorize!(:show, fin_account)
    wsjrdp_apply_table_filter(transactions_table_state, redirect_to: wsjrdp_fin_account_path(fin_account))
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

  # The resolved state of the wallet's transactions table
  # (Fin::MossTransactionsTable#transactions).
  def transactions_table_state = wsjrdp_expandable_table_state(WALLET_POLICY)

  private

  # The wallet's transactions: those booked on this account.
  def moss_transactions_base = MossTransaction.where(fin_account_id: fin_account.id)

  def authorize_action
    authorize!(:show, WsjrdpFinAccount)
  end

  def return_url
    return_url_or_fallback url_for(fin_account)
  end

  # Back to where the form was opened, now showing what was saved. A form in a
  # frame leaves it (stream action redirect_top), so the page around it -- the
  # head line and the tabs, or the list's row -- shows the new values too: the
  # account's page with the detail open, or the list with the account's row open.
  # A failed save stays in the frame (#update renders the edit page, which
  # answers a frame request with the frame).
  def redirect_after_save
    if !turbo_frame_request?
      redirect_to wsjrdp_fin_account_path(fin_account, details: "open"), status: :see_other
    elsif detail_frame_on_page?
      redirect_top wsjrdp_fin_account_path(fin_account, details: "open")
    else
      redirect_top wsjrdp_fin_accounts_path(ACCOUNTS_POLICY.param_name(:open) => fin_account.id)
    end
  end

  def redirect_top(url)
    render turbo_stream: helpers.turbo_stream_action_tag(:redirect_top, url: url)
  end

  # Back to the reading view: in a frame the detail itself, else wherever the
  # edit page was reached from.
  def cancel_url
    turbo_frame_request? ? wsjrdp_fin_account_path(fin_account) : return_url
  end

  def fin_account_path(entry = nil)
    url_for(entry.nil? ? fin_account : entry)
  end

  def model_params
    params.require(:wsjrdp_fin_account)
  end

  def permitted_attrs
    if can?(:admin_finance, fin_account)
      [
        :short_name, :description,
        :account_identification,
        :opening_balance_cents, :opening_balance_eur,
        :opening_balance_currency, :opening_balance_date,
        :iban, *TOP_UP_ATTRS,
        :owner_name, :owner_address,
        :servicer_name, :servicer_short_name, :servicer_bic, :servicer_address,
        :account_product,
        :status,
        :bookkeeping_account_number, :bookkeeping_account_type,
        :visibility,
        :position
      ]
    elsif can?(:update, fin_account)
      [:short_name, :description]
    else
      []
    end
  end

  # An account with an IBAN keeps its top-up fields out of the save, whatever was
  # sent (WsjrdpFinAccount#top_up_applicable?). The IBAN that counts is the one
  # this very save leaves behind.
  def permitted_params
    attrs = model_params.permit(permitted_attrs)
    iban = attrs.key?(:iban) ? attrs[:iban] : fin_account.iban
    iban.present? ? attrs.except(*TOP_UP_ATTRS) : attrs
  end
end
