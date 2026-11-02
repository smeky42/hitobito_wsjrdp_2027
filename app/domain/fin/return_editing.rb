# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the edit page of a return (/fin/payments/returns/:id/edit) lets change:
# the fields of the return's page that a bank transaction lets edit
# (Fin::WsjrdpCamtTransactionsController#permitted_attrs) -- its processing
# status and its comment. Each field with the input it gets (Fin::DetailHelper).
module Fin::ReturnEditing
  FIELDS = {return_status: :wide_select, comment: :textarea}.freeze

  module_function

  # The statuses a return can be set to, as the select offers them
  # (Settings.return_debit_status).
  def statuses = Settings.return_debit_status.to_h.transform_keys(&:to_s)

  # The params the update takes; a status only one of .statuses.
  def permitted(params)
    attrs = params.permit(FIELDS.keys)
    attrs.delete(:return_status) if attrs.key?(:return_status) && !statuses.key?(attrs[:return_status])
    attrs
  end
end
