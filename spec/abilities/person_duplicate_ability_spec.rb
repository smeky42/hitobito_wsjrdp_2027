# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Nobody merges people (Wsjrdp2027::Ability#forbid_person_merges); ignoring a
# duplicate in the core's list stays allowed.
describe PersonDuplicateAbility do
  let(:duplicate) { PersonDuplicate.create!(person_1: people(:yp_a_1), person_2: people(:yp_a_2)) }
  let(:root_admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:root_user) { Fabricate(:person, email: Settings.root_email) }

  it "lets an admin ignore a duplicate but not merge it" do
    ability = Ability.new(root_admin)

    expect(ability.can?(:ignore, duplicate)).to be(true)
    expect(ability.can?(:merge, duplicate)).to be(false)
  end

  it "forbids the merge to the root user too" do
    expect(root_user).to be_root
    ability = Ability.new(root_user)

    expect(ability.can?(:manage_person_duplicates, groups(:root))).to be(true)
    expect(ability.can?(:merge, duplicate)).to be(false)
  end
end
