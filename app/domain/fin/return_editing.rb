# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Fin::ReturnEditing
  FIELDS = {return_status: :wide_select, comment: :textarea}.freeze

  module_function

  # The statuses a return can be set to, as the select offers them
  # (Settings.return_debit_status).
  def statuses = Settings.return_debit_status.to_h.transform_keys(&:to_s)

  # Is this one of them?
  def status?(value) = statuses.key?(value.to_s)

  # The select's options, label first.
  def status_options = statuses.map { |value, label| [label, value] }

  # The params the update takes.
  def permitted(params) = params.permit(FIELDS.keys)
end
