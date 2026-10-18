# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The reading and the edit page of a debit (a pre-notification), as both its
# places show them: in the Zahlungsverkehr area (Fin::DirectDebitsController,
# /fin/payments/debits/:id) and under its person (Fin::WsjrdpDirectDebitPre-
# NotificationsController, /fin/pn/:id). Both render fin/direct_debits/_detail
# and change what Fin::DebitEditing lets change; the including controller
# names its own pages (#debit_page_path, #edit_debit_page_path).
#
# Another page may send the reader to either with `return_url`, a path of
# this application (e.g. `direct_debit_path(id, return_url: request.fullpath)`):
# the reading page then leads back there, the edit page keeps it, and a save
# returns to it.
module Fin::DebitPages
  extend ActiveSupport::Concern

  included do
    helper_method :return_path, :debit_page_place
  end

  private

  def find_debit = Fin::PaymentQueries.debits.find(params[:id])

  # Where the page stands: :area (Zahlungsverkehr) or :person.
  def debit_page_place = :area

  # Saves and goes back to the page the reader came from (`return_url`), else
  # to the reading page -- or stays on the edit page ("Speichern und weiter
  # bearbeiten"); a failed save shows the edit page again with what was typed
  # and the errors.
  def save_debit(debit)
    changes = Fin::DebitEditing.permitted(debit, params.require(:wsjrdp_direct_debit_pre_notification),
      manage: can?(:admin_finance, debit))
    if debit.update(changes)
      target = if params[:stay].present?
        edit_debit_page_path(debit, return_url: return_path)
      else
        return_path || debit_page_path(debit)
      end
      redirect_to target, notice: t("fin.payments.debit_saved", id: debit.id)
    else
      @ctx = Fin::AttrFormatContext.regular
      render :edit, status: :unprocessable_entity
    end
  end

  # The `return_url` param as a path with its query, if it names one of this
  # application; nil for anything else (another host, a protocol-relative
  # "//host", garbage), so no link leads off the site.
  def return_path
    return @return_path if defined?(@return_path)

    url = params[:return_url].to_s
    @return_path = (local_path(url) if url.start_with?("/") && !url.start_with?("//"))
  end

  def local_path(url)
    uri = URI.parse(url)
    return nil if uri.scheme || uri.host

    uri.query ? "#{uri.path}?#{uri.query}" : uri.path
  rescue URI::Error
    nil
  end
end
