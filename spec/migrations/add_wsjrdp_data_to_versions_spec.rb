# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require HitobitoWsjrdp2027::Wagon.root.join("db/migrate/20261020000100_add_wsjrdp_data_to_versions.rb")

# The tag entries written before wsjrdp_data get the tag's name there from
# their object_changes; the columns themselves exist in the test database.
describe AddWsjrdpDataToVersions do
  let(:migration) { described_class.new }
  let(:person) { people(:yp_a_1) }

  def quietly(&block) = ActiveRecord::Migration.suppress_messages(&block)

  def old_tag_entry(event, object_changes)
    PaperTrail::Version.create!(item: person, main: person, event: event, object_changes: object_changes)
  end

  it "fills the tag's name of old tag entries and leaves the others alone" do
    added = old_tag_entry("wsjrdp_add_tag", YAML.dump({"tag" => [nil, "Bus 3"]}))
    removed = old_tag_entry("wsjrdp_remove_tag", YAML.dump({"tag" => ["Bus 2", nil]}))
    unreadable = old_tag_entry("wsjrdp_add_tag", "tag: [unclosed")
    filled = PaperTrail::Version.create!(item: person, main: person, event: "wsjrdp_add_tag",
      wsjrdp_data: {"tag_name" => "as is"}, object_changes: YAML.dump({"tag" => [nil, "other"]}))
    other = PaperTrail::Version.create!(item: person, main: person, event: "update",
      object_changes: YAML.dump({"tag" => [nil, "not a tag entry"]}))

    expect(quietly { migration.backfill_tag_data }).to eq([2, 1])

    expect(added.reload.wsjrdp_data).to eq("tag_name" => "Bus 3")
    expect(removed.reload.wsjrdp_data).to eq("tag_name" => "Bus 2")
    expect(unreadable.reload.wsjrdp_data).to eq({})
    expect(filled.reload.wsjrdp_data).to eq("tag_name" => "as is")
    expect(other.reload.wsjrdp_data).to eq({})
  end
end
