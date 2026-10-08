# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One row of a person's deregistration: a withdrawal, a termination or a
# cancellation of the registration, with its dates, the compensation and the
# form. number counts the rows of a person, a replacing row included.
#
# The row is written down in steps (STATUSES) and fixed in two:
#
# - From form_sent on, what the sent form says stays: kind, issue, the dates,
#   the deadline, the entered compensation, show_contractual_compensation,
#   form_options, form_sent_at, form_snapshot and the sent form
#   (sent_form_document_id). Changing one of them means a new row: the old
#   one becomes superseded, the new one points at it (replaces) and gets the
#   next number.
# - A row in a final status (FINAL_STATUSES, closed_at set) is done.
#
# signed_form_document_id points at the form that came back signed,
# signed_form_received_at says when it came in.
# comment and additional_info stay changeable. Every change is written down
# as a WsjrdpDeregistrationEvent.
class WsjrdpDeregistration < ActiveRecord::Base
  STATUSES = %w[
    recorded form_created form_sent signed_form_received refund_initiated refund_booked
    confirmation_sent finished canceled superseded deleted
  ].freeze
  FINAL_STATUSES = %w[finished canceled superseded deleted].freeze
  KINDS = %w[withdrawal termination cancellation].freeze

  validates :number, numericality: {only_integer: true, greater_than_or_equal_to: 1}
end
