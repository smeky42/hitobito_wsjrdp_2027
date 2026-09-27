# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A token with an acting person may do what both the token and the person may.
describe Wsjrdp2027::ActingPersonTokenAbility do
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "Skript", people: true,
      permission: "layer_and_below_full", acting_person: acting_person)
  end
  let(:ability) { described_class.new(token) }
  let(:other) { people(:yp_a_1) }

  context "with an admin as acting person" do
    let(:acting_person) { people(:admin) }

    it "allows what both allow" do
      expect(ability.can?(:show, other)).to be(true)
      expect(ability.can?(:update, other)).to be(true)
    end

    it "refuses what only the person may, such as :log" do
      expect(Ability.new(acting_person).can?(:log, other)).to be(true)
      expect(ability.can?(:log, other)).to be(false)
      expect { ability.authorize!(:log, other) }.to raise_error(CanCan::AccessDenied)
    end

    it "has the person as user, and an identifier of token and person" do
      expect(ability.user).to eq(acting_person)
      expect(ability.identifier).to eq("token-#{token.id}-person-#{acting_person.id}")
    end
  end

  context "with a participant as acting person" do
    let(:acting_person) { people(:yp_a_2) }

    it "refuses what only the token may" do
      expect(TokenAbility.new(token).can?(:update, other)).to be(true)
      expect(ability.can?(:update, other)).to be(false)
      expect(ability.cannot?(:update, other)).to be(true)
    end
  end
end
