# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::LogEntry do
  let(:person) { people(:yp_a_1) }
  let(:group) { groups(:unit_a) }

  describe ".record!" do
    it "writes a version of the event with its data" do
      version = described_class.record!(group, "wsjrdp_something", {"a" => 1},
        main: person, whodunnit: people(:admin).id.to_s, additional_info: {"source" => "spec"})

      expect(version.reload).to have_attributes(item: group, main: person, event: "wsjrdp_something",
        whodunnit: people(:admin).id.to_s, whodunnit_type: "Person", wsjrdp_data: {"a" => 1},
        additional_info: {"source" => "spec"}, object_changes: nil)
    end

    it "has {} for no data" do
      expect(described_class.record!(person, "wsjrdp_something").reload)
        .to have_attributes(main: person, wsjrdp_data: {}, additional_info: {})
    end
  end

  describe ".note!" do
    it "writes category and message over the data, and any category and message" do
      version = described_class.note!(person, category: "unknown_category", message: "",
        data: {category: "lost", collection_date: "2026-11-05"})

      expect(version.reload).to have_attributes(event: "wsjrdp_note",
        wsjrdp_data: {"category" => "unknown_category", "message" => "", "collection_date" => "2026-11-05"})
    end

    it "is found by its category through @>" do
      note = described_class.note!(person, category: "pre_notification", message: "informiert")
      described_class.note!(person, category: "other", message: "anderes")

      found = PaperTrail::Version.where("wsjrdp_data @> ?", {category: "pre_notification"}.to_json)
      expect(found).to contain_exactly(note)
    end
  end

  describe "tagging" do
    it "logs the tag's name in wsjrdp_data and in object_changes" do
      person.tag_list.add("Bus 3")
      person.save!
      person.tag_list.remove("Bus 3")
      person.save!

      versions = PaperTrail::Version.where(main: person, event: %w[wsjrdp_add_tag wsjrdp_remove_tag]).order(:id)
      expect(versions.map { |version| [version.event, version.wsjrdp_data, YAML.load(version.object_changes)] })
        .to eq([["wsjrdp_add_tag", {"tag_name" => "Bus 3"}, {"tag" => [nil, "Bus 3"]}],
          ["wsjrdp_remove_tag", {"tag_name" => "Bus 3"}, {"tag" => ["Bus 3", nil]}]])
    end
  end
end
