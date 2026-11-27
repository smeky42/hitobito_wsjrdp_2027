# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The suppliers (GET /v1/suppliers) into wsjrdp_personal_accounts, as
  # creditors. Next to each Moss reference goes what it names in Hitobito
  # (number, team name). Account holder and type come from the CSV export.
  class Suppliers < MasterPart
    self.key = "moss_api.master_data.suppliers"
    self.depends_on = [Teams.key, CostCenters.key, Spheres.key, LedgerAccounts.key, PaymentTerms.key, TaxRates.key]
    self.path = "v1/suppliers"
    self.model = WsjrdpPersonalAccount
    self.sort_orders = %w[supplier_number -supplier_number].freeze
    REFERENCES = {"defaultTeamId" => "Team", "defaultExpenseAccountId" => "Sachkonto",
                  "defaultCostCenterId" => "Kostenstelle", "defaultCostCarrierId" => "Sphäre",
                  "paymentTermId" => "Zahlungsbedingung", "defaultVatRateId" => "Steuersatz"}.freeze

    def self.number(code) = super&.then { |number| number if WsjrdpPersonalAccount::CREDITOR_NUMBER.match?(number) }

    private

    def more_attributes(record)
      address = record["address"] || {}
      {account_kind: "CREDITOR", moss_default_currency: text(record["currency"]), moss_vat_id: text(record["vatIdNo"]),
       iban: text(record["iban"]), bic: text(record["bic"]), moss_default_payment_method: text(record["defaultPaymentMethod"]),
       street: text(address["streetAddress"]), post_code: text(address["postCode"]), city: text(address["city"]),
       country: text(address["country"]),
       default_moss_team_uuid: record["defaultTeamId"], moss_default_team_name: team_names[record["defaultTeamId"]],
       default_moss_expense_account_uuid: record["defaultExpenseAccountId"],
       moss_default_ledger_account_number: references[LedgerAccounts][record["defaultExpenseAccountId"]],
       default_moss_cost_center_uuid: record["defaultCostCenterId"],
       moss_default_cost_center_number: references[CostCenters][record["defaultCostCenterId"]],
       default_moss_cost_carrier_uuid: record["defaultCostCarrierId"],
       moss_default_sphere_number: references[Spheres][record["defaultCostCarrierId"]],
       default_moss_payment_term_uuid: record["paymentTermId"], default_moss_vat_rate_uuid: record["defaultVatRateId"]}
    end

    # {part => {Moss UUID => number}}
    def references = @references ||= [LedgerAccounts, CostCenters, Spheres].index_with { |part| numbers_of(part) }

    def known_uuids(part) = known(part.model, part.uuid_column, part.key, part.data_name)

    def notices(records, changes, table)
      super + [important("unknown_reference", unknown_references(records))].reject { |notice| notice.keys.empty? }
    end

    # {UUID => "label → Sachkonto <uuid>, …"} of the suppliers naming what no list has, or
    # what has no number in Hitobito.
    def unknown_references(records)
      known = {"defaultTeamId" => team_names.keys.to_set,
               "defaultExpenseAccountId" => references[LedgerAccounts].compact.keys.to_set,
               "defaultCostCenterId" => references[CostCenters].compact.keys.to_set,
               "defaultCostCarrierId" => references[Spheres].compact.keys.to_set,
               "paymentTermId" => known_uuids(PaymentTerms), "defaultVatRateId" => known_uuids(TaxRates)}
      records.filter_map do |record|
        missing = REFERENCES.filter_map { |field, name| "#{name} #{record[field]}" if record[field] && !known[field].include?(record[field]) }
        [record["id"], "#{item_label(record)} → #{missing.join(", ")}"] if missing.any?
      end.to_h
    end
  end
end
