# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One DATEV Buchungsstapel (= one Primanota = one DTVF export file). Populated
# from the DTVF header line by the importer. Its bookings point back via the
# optional datev_booking_batch_id.
#
# A Stapel is uniquely identified by the stable header coordinates
# (consultant_number, client_number, period_from, period_to, label) -- see the
# unique index. The reconstructed primanota_number and the file_sequence are NOT
# part of the identity (they depend on the export as a whole, not on the Stapel).
class DatevBookingBatch < ActiveRecord::Base
  has_many :datev_bookings, dependent: :nullify

  validates :consultant_number, :client_number, :period_from, :period_to, :label,
    presence: true
end
