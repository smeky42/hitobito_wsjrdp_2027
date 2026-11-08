# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What a statement row needs to be a LEG of an Umbuchung (WsjrdpInternalTransfer):
# a key that names it across the two tables ("camt:12", "moss:34") and the two
# marks a user leaves when a suggestion of Fin::InternalTransferDetection is
# wrong, kept in the row's additional_info like denylist_subject_candidates:
#
#   not_internal_transfer                  true: this row is no transfer at all
#                                          ("Keine Umbuchung")
#   denylist_internal_transfer_candidates  the keys of rows that are not its
#                                          counterpart ("keine davon")
#
# Included by WsjrdpCamtTransaction and MossTransaction.
module WsjrdpInternalTransferLeg
  extend ActiveSupport::Concern

  NOT_TRANSFER_KEY = "not_internal_transfer"
  DENYLIST_KEY = "denylist_internal_transfer_candidates"

  def internal_transfer_leg_source = is_a?(MossTransaction) ? "moss" : "camt"

  def internal_transfer_leg_key = "#{internal_transfer_leg_source}:#{id}"

  def not_internal_transfer? = additional_info.to_h[NOT_TRANSFER_KEY] == true

  def denied_internal_transfer_candidates = Array(additional_info.to_h[DENYLIST_KEY])

  def mark_not_internal_transfer!
    write_internal_transfer_info(NOT_TRANSFER_KEY => true)
  end

  def deny_internal_transfer_candidate!(key)
    keys = (denied_internal_transfer_candidates + [key]).uniq
    write_internal_transfer_info(DENYLIST_KEY => keys)
  end

  private

  # Straight to the column: the marks are the app's, no import rewrites
  # additional_info, and the row's own validations have nothing to say about
  # them.
  def write_internal_transfer_info(changes)
    update_columns(additional_info: additional_info.to_h.merge(changes), updated_at: Time.current)
  end
end
