# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::PaperTrail::YamlSerializer do
  let(:plan) { [BigDecimal(2026), BigDecimal(0), BigDecimal("312.5"), BigDecimal("0.01")] }

  it "is PaperTrail's serializer" do
    expect(PaperTrail.serializer).to eq(described_class)
  end

  it "writes the plan's decimals as strings and reads them back as BigDecimal" do
    yaml = described_class.dump({"wsjrdp_raw_installments_eur" => [nil, plan]})

    # Compared with the YAML of the strings, not a literal: libyaml versions
    # differ in how they write nil ("-" or "- ").
    expect(yaml).to eq(YAML.dump({"wsjrdp_raw_installments_eur" => [nil, %w[2026.0 0.0 312.5 0.01]]}))
    expect(yaml).to include("- - '2026.0'\n  - '0.0'\n  - '312.5'\n  - '0.01'\n")
    expect(described_class.load(yaml)).to eq("wsjrdp_raw_installments_eur" => [nil, plan])
  end

  it "writes every other attribute as PaperTrail does" do
    object = {"wsjrdp_total_fee_reduction" => [BigDecimal(0), BigDecimal(1700)], "first_name" => %w[A B]}

    expect(described_class.dump(object)).to eq(PaperTrail::Serializers::YAML.dump(object))
    expect(described_class.dump(object)).to include("!ruby/object:BigDecimal")
  end

  it "reads plans written with BigDecimal tags" do
    legacy = PaperTrail::Serializers::YAML.dump({"wsjrdp_raw_installments_eur" => plan})

    expect(described_class.load(legacy)).to eq("wsjrdp_raw_installments_eur" => plan)
  end

  describe "on a person" do
    let(:person) { people(:yp_a_1) }

    it "writes the plan as strings in object and object_changes, changeset and reify see BigDecimal" do
      with_versioning do
        person.update!(wsjrdp_raw_installments_eur: plan)
        person.update!(wsjrdp_raw_installments_eur: plan.first(2))
      end

      version = person.versions.reorder(:id).last
      expect(version.object_changes).to include("- '312.5'")
      expect(version.object_changes).not_to include("BigDecimal")
      expect(version.object).to include("- '312.5'")
      expect(version.changeset["wsjrdp_raw_installments_eur"]).to eq([plan, plan.first(2)])
      expect(version.reify.wsjrdp_raw_installments_eur).to eq(plan)
    end
  end
end
