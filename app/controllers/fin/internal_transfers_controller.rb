# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Umbuchungen (/fin/acc/internal_transfers), a tab of Konten & Wallets
# (Sheet::Fin::Accounts): the transfers between the contingent's own accounts
# (WsjrdpInternalTransfer). See doc/fin/internal_transfers.md.
#
#   index       the suggestions of Fin::InternalTransferDetection on top, the
#               transfers below as an expandable table (one view per status)
#   show        a transfer's page -- or, for a frame request, its detail alone:
#               a row of the list asks for it, and so does "Abbrechen"
#   new/create  a transfer put together by hand
#   edit/update the comment and the legs of a transfer; a transfer left without
#               legs is dissolved
#   destroy     dissolves a transfer; its rows stay as they are
#   link        links the chosen suggestions; dismiss marks rows or pairs as
#               no transfer
#   link_unique the import scripts' API: links every unique suggestion. Only a
#               service token reaches it (and no CSRF token is asked of it).
#
# A form answers like the account detail does (Fin::WsjrdpFinAccountsController):
# from a frame it leaves the frame (stream action redirect_top) for the page it
# came from -- the transfer's page with the detail open, or the list with the
# transfer's row open --, a failed save stays in the frame.
class Fin::InternalTransfersController < Fin::FinController
  include Wsjrdp::TableStateful

  # The id prefix of the frame the detail stands in on a transfer's own page;
  # the list's rows ask with theirs ("bkframe-it-<id>").
  PAGE_FRAME_PREFIX = "itpage"

  TRANSFERS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::InternalTransfersColumns::COLUMNS.codec,
    cols: {default: Fin::InternalTransfersColumns::COLUMNS.default_keys},
    sort: {hidden: [["date", "desc"]]},
    per_page: {default: 50},
    filter: {policy: :url, schema: Fin::InternalTransfersFilterSchema,
             presets: Fin::InternalTransfersFilterSchema::PRESETS}

  # "Buchungen der Umbuchung" in a transfer's detail: its legs, all on one page.
  LEGS_POLICY = wsjrdp_expandable_table_policy prefix: "itl",
    columns: Fin::InternalTransferLegsColumns::COLUMNS.codec,
    cols: {default: Fin::InternalTransferLegsColumns::COLUMNS.default_keys},
    per_page: {default: :all}

  skip_forgery_protection only: :link_unique

  before_action :authorize_class, only: [:index, :apply]
  before_action :authorize_create, only: [:new, :create, :link, :dismiss, :link_unique]

  helper_method :transfers, :transfer, :detection, :detail_frame_on_page?, :page_frame_id,
    :transfers_table_state, :transfer_legs_rows

  def index
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful).
  def apply
    wsjrdp_apply_table_filter(transfers_table_state, redirect_to: internal_transfers_path)
  end

  def show
    authorize!(:show, transfer)
    render(:detail_frame, layout: false) if turbo_frame_request?
  end

  def new
    @transfer = WsjrdpInternalTransfer.new
  end

  def create
    records = leg_records(params[:add_legs])
    if records.empty?
      @transfer = WsjrdpInternalTransfer.new(comment: params.dig(:wsjrdp_internal_transfer, :comment).to_s)
      @transfer.errors.add(:base, "Bitte mindestens eine Buchung auswählen.")
      return render(:new, status: 422)
    end
    @transfer = WsjrdpInternalTransfer.link!(records, meta: link_meta("manual"),
      comment: params.dig(:wsjrdp_internal_transfer, :comment))
    redirect_after_save
  rescue WsjrdpInternalTransfer::LegTaken
    @transfer = WsjrdpInternalTransfer.new
    @transfer.errors.add(:base, "Eine der Buchungen gehört inzwischen zu einer anderen Umbuchung.")
    render :new, status: 422
  end

  def edit
    authorize!(:update, transfer)
  end

  def update
    authorize!(:update, transfer)
    transfer.change!(comment: params.dig(:wsjrdp_internal_transfer, :comment),
      add: leg_records(params[:add_legs]), remove: leg_records(params[:remove_legs]), by: actor)
    if transfer.destroyed?
      redirect_top_or_to(internal_transfers_path, notice: "#{transfer} aufgelöst.")
    else
      redirect_after_save
    end
  rescue WsjrdpInternalTransfer::LegTaken
    transfer.reload.errors.add(:base, "Eine der Buchungen gehört inzwischen zu einer anderen Umbuchung.")
    render :edit, status: 422
  end

  def destroy
    authorize!(:destroy, transfer)
    transfer.destroy!
    redirect_top_or_to(internal_transfers_path, notice: "#{transfer} aufgelöst.")
  end

  # The suggestions box: links the checked unique pairs and the pair picked in
  # each group (params[:pairs], params[:choice]), or marks them (#dismiss).
  def link
    keys = Array(params[:pairs]) + Array(params[:choice]&.values).reject { |value| value == "none" }
    linked = link_pairs(keys, "suggestion")
    redirect_to internal_transfers_path, notice: "#{linked} #{(linked == 1) ? "Umbuchung" : "Umbuchungen"} verknüpft."
  end

  # "Ausgewählte verwerfen" (pairs: each row denies the other), "keine davon"
  # (every pair of the group) and "Keine Umbuchung" (legs: the row is no
  # transfer at all).
  def dismiss
    pair_keys = Array(params[:pairs]) + Array(params[:group_pairs])
    pair_keys.each do |key|
      from, to = Fin::InternalTransferLeg.find_all(key.split(">", 2))
      from.record.deny_internal_transfer_candidate!(to.key)
      to.record.deny_internal_transfer_candidate!(from.key)
    end
    Fin::InternalTransferLeg.find_all(params[:legs]).each { |leg| leg.record.mark_not_internal_transfer! }
    redirect_to internal_transfers_path, notice: "Vorschläge verworfen."
  end

  # POST /fin/acc/internal_transfers/link_unique.json, for the import scripts.
  def link_unique
    return head(:forbidden) unless current_service_token

    found = Fin::InternalTransferDetection.new
    linked = link_pairs(found.unique.map(&:key), "api")
    render json: {linked: linked, ambiguous: found.ambiguous.size, waiting: found.waiting.size,
                  without_counterpart: found.without_counterpart.size}
  end

  def transfer
    @transfer ||= WsjrdpInternalTransfer.find(params[:id])
  end

  def detection
    @detection ||= Fin::InternalTransferDetection.new
  end

  def transfers_table_state = wsjrdp_expandable_table_state(TRANSFERS_POLICY)

  # The transfers the filter leaves, as rows (Fin::InternalTransfersColumns::Row).
  def transfers
    @transfers ||= begin
      rows = WsjrdpInternalTransfer.order(:id).map { |record| Fin::InternalTransfersColumns::Row.new(record) }
      rows = transfers_table_state.filter.scope(rows)
      Wsjrdp::ExpandableTableRows.new(transfers_table_state, rows,
        sort: Fin::InternalTransfersColumns.sort_lambdas, tiebreaker: ->(row) { -row.transfer.id })
    end
  end

  # The legs of a transfer as the rows of its legs table, in the transfer's
  # own order until a header sorts them.
  def transfer_legs_rows(record)
    legs = record.transfer_legs
    order = legs.each_with_index.to_h
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(LEGS_POLICY), legs,
      sort: Fin::InternalTransferLegsColumns.sort_lambdas, tiebreaker: ->(leg) { order[leg] })
  end

  def page_frame_id(record) = helpers.wsjrdp_detail_frame_id(PAGE_FRAME_PREFIX, record.id)

  def detail_frame_on_page? = turbo_frame_request_id == page_frame_id(transfer)

  private

  def authorize_class = authorize!(:show, WsjrdpInternalTransfer)

  def authorize_create = authorize!(:create, WsjrdpInternalTransfer)

  # Links every pair named by its key ("camt:1>moss:2"); a pair whose rows are
  # taken by now is skipped. Returns how many were linked.
  def link_pairs(keys, source)
    rules = detection.pairs.index_by(&:key)
    keys.uniq.count do |key|
      legs = Fin::InternalTransferLeg.find_all(key.split(">", 2))
      meta = link_meta(source).merge("rule" => rules[key]&.rule&.to_s).compact
      WsjrdpInternalTransfer.link!(legs.map(&:record), meta: meta)
      true
    rescue WsjrdpInternalTransfer::LegTaken
      false
    end
  end

  def link_meta(source) = {"source" => source, "by" => actor}

  # Who did it: the person, or the API key of the import scripts.
  def actor
    if current_person
      {"person_id" => current_person.id, "name" => current_person.to_s}
    elsif current_service_token
      {"service_token_id" => current_service_token.id, "name" => current_service_token.name}
    end
  end

  # The legs named by "camt:12"-like keys, as records; blanks are ignored.
  def leg_records(keys)
    Fin::InternalTransferLeg.find_all(Array(keys).compact_blank).map(&:record)
  end

  def redirect_after_save
    if !turbo_frame_request?
      redirect_to internal_transfer_path(transfer, details: "open"), status: :see_other
    elsif detail_frame_on_page?
      redirect_top internal_transfer_path(transfer)
    else
      redirect_top internal_transfers_path(TRANSFERS_POLICY.param_name(:open) => transfer.id)
    end
  end

  def redirect_top_or_to(url, notice:)
    flash[:notice] = notice
    turbo_frame_request? ? redirect_top(url) : redirect_to(url, status: :see_other)
  end

  def redirect_top(url)
    render turbo_stream: helpers.turbo_stream_action_tag(:redirect_top, url: url)
  end
end
