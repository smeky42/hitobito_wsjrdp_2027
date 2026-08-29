# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One DATEV Buchungsstapel (= one Primanota = one DTVF export
# file). Populated from the DTVF header line by the importer. A batch
# (Buchungsstapel) is uniquely identified by the stable header
# coordinates (consultant_number, client_number, period_from,
# period_to, label) -- see the unique index. The reconstructed
# primanota_number is NOT part of the identity.
class DatevBookingBatch < ActiveRecord::Base
  has_many :bookings, class_name: "DatevBooking",
    inverse_of: :batch, dependent: :nullify

  # Last day of the financial year.
  def financial_year_end = financial_year_start && financial_year_start + 1.year - 1.day

  # Financial year = calendar year the financial year ends in.
  def financial_year = financial_year_end&.year

  validates :consultant_number, :client_number, :period_from, :period_to, :label,
    presence: true
end
