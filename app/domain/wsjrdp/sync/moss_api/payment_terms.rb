# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The payment terms (GET /v1/payment-terms) into moss_payment_terms.
  class PaymentTerms < ListPart
    self.key = "moss_api.master_data.payment_terms"
    self.path = "v1/payment-terms"
    self.model = MossPaymentTerm
    self.uuid_column = "moss_payment_term_uuid"
    self.sort_orders = %w[number -number].freeze

    private

    def attributes(record)
      {moss_payment_term_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       description: text(record["description"]), code: text(record["code"]),
       net_due_days: record["netDueDays"], month_end_advances: record["monthEndAdvances"],
       due_date_calculation_type: record["dueDateCalculationType"], status: record["status"],
       lines: Array(record["lines"])}
    end

    def label(record) = record["description"].presence || record["code"].presence || record["moss_payment_term_uuid"]
  end
end
