# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Wsjrdp2027::Person applies remove_schema_validations (WsjrdpSchemaValidationHelper)
# to two columns: it strips the core's two-gender inclusion (re-declared with
# three values via i18n_enum) and the presence validator validates_by_schema
# derives from the NOT NULL wsjrdp_user_preferences column.
describe Person do
  describe "gender (inclusion re-declared with three values)" do
    let(:person) { people(:cmt_leader) }

    it "carries exactly one inclusion validator after the remove-and-re-add" do
      inclusion = Person.validators_on(:gender)
        .select { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }

      expect(inclusion.size).to eq(1)
    end

    it "accepts all three genders, the wagon's d included" do
      %w[m w d].each do |g|
        person.gender = g
        person.valid?
        expect(person.errors[:gender]).to be_empty, "expected #{g.inspect} to be valid"
      end
    end

    it "allows a blank gender" do
      person.gender = nil
      person.valid?

      expect(person.errors[:gender]).to be_empty
    end

    it "still rejects an unknown gender (the validator is live, not just present)" do
      person.gender = "x"
      person.valid?

      expect(person.errors[:gender]).to be_present
    end
  end

  describe "wsjrdp_user_preferences (schema presence removed)" do
    it "has no presence validator despite the NOT NULL column" do
      expect(Person.validators_on(:wsjrdp_user_preferences)).to be_empty
    end

    it "does not flag a new Person's blank {} preferences" do
      person = Person.new
      person.valid?

      expect(person.errors[:wsjrdp_user_preferences]).to be_empty
    end
  end
end
