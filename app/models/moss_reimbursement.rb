# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A REIMBURSEMENT payout (STI subclass of MossTransaction).
#
# The only kind with a real middle level: one payout bundles several expenses, so
# it has N MossExpenses, and each of those may itself be split across accounts
# (rarely). That split detail exists ONLY in the Moss
# reimbursement export -- the balance-movements export collapses it -- which is
# why the importer reads both and why the migration needs the enrichment step.
class MossReimbursement < MossTransaction
  def moss_record_url
    return super if moss_reimbursement_uuid.blank?

    "#{MOSS_APP_URL}/reimbursements/all/#{moss_reimbursement_uuid}"
  end

  def moss_export_url
    return super if moss_reimbursement_uuid.blank?

    "#{MOSS_APP_URL}/export/reimbursements/#{moss_reimbursement_uuid}"
  end

  # `Submitted On` (Moss's expenseTime of the reimbursement header, the day
  # the claim was submitted) is the DATEV date anchor, matched against
  # datev_bookings.booking_date (the Belegdatum); the payment and booking
  # dates are Moss processing dates.
  def datev_date_anchor = submitted_on

  # The claim's title (Moss: Name); the Buchungstext is its description.
  def display_name = transaction_name
end
