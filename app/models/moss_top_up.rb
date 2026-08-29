# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A wallet TOP-UP (STI subclass of MossTransaction): money moved INTO the Moss
# wallet, so the amount is POSITIVE where every other kind is negative, and the
# booking carries no expense account (it only touches wallet 36100 and transit
# 13720).
#
# Recognised on import by having neither a linked invoice nor a linked
# reimbursement. The funding bank account is exported only as the truncated
# "<organisation> - <IBAN>" text in `top_up_sender` (Moss cuts the field after
# 60 characters), so the link to the matching bank booking
# (`camt_transaction`) is made on amount + date.
class MossTopUp < MossTransaction
  # A top-up is the one kind that links NOWHERE: Moss addresses it in its export
  # route by an internal id of its own, which no export carries and no column
  # here stores, and the transaction uuid put in that id's place resolves to
  # nothing. Both readers therefore answer nil and every view renders no Moss
  # link for a top-up (the /transactions/all/ form is a dead link here too).
  def moss_record_url = nil

  def moss_export_url = nil

  def expense = expenses.first

  # In DATEV a top-up is the step-3 pair 36100 -> creditor and 13720 -> creditor,
  # both carrying the transaction uuid in Belegfeld 1, so it matches by uuid.
  def datev_date_anchor = payment_date

  def display_name = "Einzahlung"

  def display_text = top_up_sender
end
