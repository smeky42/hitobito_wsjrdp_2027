# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# GET /fin/transaction_picker: the results of the shared transaction picker
# (shared/wsjrdp/_transaction_picker, doc/wsjrdp/transaction_picker.md) --
# bank and Moss transactions of the own accounts, filtered by
# Fin::TransactionSearch, answered as the picker's results frame. Reading
# only: what a row is picked for is the host form's business.
class Fin::TransactionPickerController < Fin::FinController
  helper_method :search, :picker_id

  def index
    sources.each { |source| authorize!(:show, Fin::InternalTransferLeg::SOURCES.fetch(source).constantize) }
    render layout: false
  end

  def search
    @search ||= Fin::TransactionSearch.new(sources: sources, sign: params[:sign].presence_in(%w[in out]),
      accounts: list(:accounts), from: date(:from), to: date(:to), amount: params[:amount],
      target: params[:target].presence, text: params[:q], linked: params[:linked] == "1",
      exclude: list(:exclude), anchor: date(:anchor))
  end

  # The picker the frame belongs to; only word characters and dashes.
  def picker_id = params[:picker].to_s.gsub(/[^\w-]/, "").presence || "picker"

  private

  def sources
    (list(:sources) & Fin::InternalTransferLeg::SOURCES.keys).presence || Fin::InternalTransferLeg::SOURCES.keys
  end

  def list(key) = params[key].to_s.split(",").map(&:strip).compact_blank

  def date(key)
    Date.iso8601(params[key].to_s)
  rescue Date::Error
    nil
  end
end
