# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A debit (pre-notification) under its person, /fin/pn/:id and
# /fin/pn/:id/edit: the same pages as in the Zahlungsverkehr area
# (Fin::DebitPages, Fin::DirectDebitsController), under the person's sheet and
# leading back to the person's Beitrag. The person's Beitrag tab and an
# entry's page link here. A debit without a person has no page here and is
# sent to the area's.
#
# Rights as in the area: reading with :log on the pre-notification (the audit
# tier up), editing with :update (the finance tier up), see Fin::DebitEditing.
class Fin::WsjrdpDirectDebitPreNotificationsController < Fin::FinController
  include Fin::DebitPages

  before_action :load_debit

  def show
    authorize!(:log, @debit)
    @ctx = Fin::AttrFormatContext.regular
  end

  def edit
    authorize!(:update, @debit)
    @ctx = Fin::AttrFormatContext.regular
  end

  def update
    authorize!(:update, @debit)
    save_debit(@debit)
  end

  private

  # The debit with what its person's sheet needs (Sheet::Fin::Wsjrdp-
  # DirectDebitPreNotification); without a person, off to the area's page.
  def load_debit
    @debit = find_debit
    return redirect_to_area unless @debit.subject_type == "Person" && @debit.subject

    @wsjrdp_direct_debit_pre_notification = @debit
    @person = @debit.person
    @group = @debit.group
  end

  def redirect_to_area
    path = (action_name == "edit") ? edit_direct_debit_path(@debit, return_url: return_path) :
      direct_debit_path(@debit, return_url: return_path)
    redirect_to path
  end

  def debit_page_place = :person

  def debit_page_path(debit, **) = wsjrdp_direct_debit_pre_notification_path(debit, **)

  def edit_debit_page_path(debit, **) = edit_wsjrdp_direct_debit_pre_notification_path(debit, **)
end
