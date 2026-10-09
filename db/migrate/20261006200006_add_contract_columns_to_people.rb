# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The participation contract of a person, apart from status: status follows
# the documents (printed, upload, in_review, ...) and may step back after a
# confirmation; the contract does not.
#
#   contract_status        none (no contract), confirmed (in force), ended
#                          (deregistered after a confirmation)
#   contract_confirmed_at  the first confirmation of the contract in force
#   contract_ended_at      the deregistration that ended it
#   contract_confirmed_by  who confirmed (a Person, the script's
#                          Administrator, or a ServiceToken)
#
# Filled from the status changes in versions, replayed per person in order:
# a change to confirmed starts a contract unless one is in force (a later
# re-confirmation keeps the first date), a change to deregistered ends the
# contract in force; every other change -- deregistration_noted and every
# step back included -- leaves it as it is. A contract ended and confirmed
# again starts anew. Who confirmed is not in the versions in a usable form
# (the scripts write as the Administrator): every filled contract is
# recorded as confirmed by CONFIRMED_BY_PERSON_ID. The fill writes no
# versions: it records what the versions already say. Single cases the
# rules do not cover are corrected after the migration, outside the wagon.
class AddContractColumnsToPeople < ActiveRecord::Migration[7.1]
  CONFIRMED_BY_PERSON_ID = 65

  class MigrationPerson < ActiveRecord::Base
    self.table_name = "people"
  end

  def change
    add_column :people, :contract_status, :string, null: false, default: "none"
    add_column :people, :contract_confirmed_at, :datetime, null: true
    add_column :people, :contract_ended_at, :datetime, null: true
    add_reference :people, :contract_confirmed_by, polymorphic: true, null: true, index: true

    reversible { |dir| dir.up { fill_from_versions } }
  end

  private

  def fill_from_versions
    MigrationPerson.reset_column_information
    contracts_from_versions.each do |person_id, contract|
      next if contract[:contract_status] == "none"

      MigrationPerson.where(id: person_id).update_all(contract)
    end
  end

  # person id => the contract columns, replayed from the status changes.
  def contracts_from_versions
    rows = select_rows(<<~SQL.squish)
      SELECT item_id, created_at, object_changes
      FROM versions
      WHERE item_type = 'Person' AND object_changes LIKE '%status:%'
      ORDER BY item_id, created_at, id
    SQL
    rows.group_by(&:first).transform_values { |changes| replay(changes) }
  end

  def replay(changes)
    contract = {contract_status: "none", contract_confirmed_at: nil, contract_ended_at: nil,
                contract_confirmed_by_type: nil, contract_confirmed_by_id: nil}
    changes.each do |_id, created_at, object_changes|
      status = Wsjrdp2027::PaperTrail::YamlSerializer.load(object_changes)["status"]
      next unless status.is_a?(Array)

      case status.last
      when "confirmed"
        next if contract[:contract_status] == "confirmed"

        contract = {contract_status: "confirmed", contract_confirmed_at: created_at, contract_ended_at: nil,
                    contract_confirmed_by_type: "Person", contract_confirmed_by_id: CONFIRMED_BY_PERSON_ID}
      when "deregistered"
        next unless contract[:contract_status] == "confirmed"

        contract = contract.merge(contract_status: "ended", contract_ended_at: created_at)
      end
    end
    contract
  end
end
