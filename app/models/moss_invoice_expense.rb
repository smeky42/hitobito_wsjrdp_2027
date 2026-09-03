# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The expense of a Moss invoice: the invoice itself; an invoice line is a BOOKING, not another expense.
# See MossExpense for the level itself.
class MossInvoiceExpense < MossExpense
  # A shell: the invoice's dates, status, terms and reviewers are transaction
  # columns / keys (invoice_date, due_date, delivery_date, submitted_date,
  # invoice_status; see MossInvoice#datev_date_anchor).
end
