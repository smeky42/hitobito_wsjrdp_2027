# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require HitobitoWsjrdp2027::Wagon.root.join("db/migrate/20261013000100_official_passport_to_national_identity_card.rb")

# A stored official_passport was chosen as "Personalausweis" and becomes a
# national identity card; the other answers stay.
describe OfficialPassportToNationalIdentityCard do
  let(:migration) { described_class.new }
  let(:card) { people(:yp_a_1) }
  let(:passport) { people(:ul_a_1) }

  def quietly(&block) = ActiveRecord::Migration.suppress_messages(&block)

  def stored(person) = Person.where(id: person.id).pick(:jamboree_data)

  it "turns an official passport into a national identity card and back" do
    card.update_columns(jamboree_data: {"travel_document_type" => "official_passport", "nationality" => "deutsch"})
    passport.update_columns(jamboree_data: {"travel_document_type" => "ordinary_passport"})

    quietly { migration.migrate(:up) }
    expect(stored(card)).to eq("travel_document_type" => "national_identity_card",
      "travel_document_other" => "National identity card", "nationality" => "deutsch")
    expect(stored(passport)).to eq("travel_document_type" => "ordinary_passport")

    quietly { migration.migrate(:down) }
    expect(stored(card)).to eq("travel_document_type" => "official_passport", "nationality" => "deutsch")
    expect(stored(passport)).to eq("travel_document_type" => "ordinary_passport")
  end
end
