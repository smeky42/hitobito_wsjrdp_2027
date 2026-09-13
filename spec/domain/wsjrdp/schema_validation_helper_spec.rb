# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Exercises remove_schema_validations against a throwaway table with an
# anonymous model, so the two validator kinds the wagon actually removes are
# covered in isolation: the presence validator validates_by_schema derives from
# a NOT NULL jsonb column, and an inclusion validator (here from a NOT NULL
# boolean, the same class i18n_enum installs for gender). Each anonymous model
# is a fresh AR subclass with its own _validators and _validate_callbacks, so
# removals cannot leak to real models.
describe WsjrdpSchemaValidationHelper do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ActiveRecord::Base.connection.create_table(:rsv_specs, force: true) do |t|
      t.jsonb :prefs, null: false, default: {}
      t.boolean :flag, null: false
      t.string :name
      t.timestamps
    end
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ActiveRecord::Base.connection.drop_table(:rsv_specs, if_exists: true)
  end

  # A fresh model per call: validates_by_schema runs in the body (so the table
  # must already exist), adding presence on :prefs and inclusion on :flag.
  def build_model
    Class.new(ActiveRecord::Base) do
      self.table_name = "rsv_specs"
      include WsjrdpSchemaValidationHelper
      validates_by_schema
      def self.name = "RsvSpec"
    end
  end

  let(:model) { build_model }

  describe "the schema validators it targets" do
    it "starts with a presence validator on the NOT NULL jsonb column" do
      expect(model.validators_on(:prefs))
        .to include(an_instance_of(ActiveRecord::Validations::PresenceValidator))
    end

    it "starts with an inclusion validator on the NOT NULL boolean column" do
      expect(model.validators_on(:flag))
        .to include(an_instance_of(ActiveModel::Validations::InclusionValidator))
    end
  end

  describe "#remove_schema_validations" do
    it "removes the presence validator and stops it flagging a blank {} value" do
      model.remove_schema_validations(:prefs, only: :presence)

      expect(model.validators_on(:prefs)).to be_empty
      record = model.new(flag: true) # prefs defaults to {} (blank?)
      record.valid?
      expect(record.errors[:prefs]).to be_empty
    end

    it "removes the inclusion validator and stops the not-included error" do
      model.remove_schema_validations(:flag, only: :inclusion)

      expect(model.validators_on(:flag)).to be_empty
      record = model.new(flag: nil)
      record.valid?
      expect(record.errors[:flag]).to be_empty
    end

    it "removes the validate callback too, not just the registry entry" do
      # A registry-only removal would leave the callback validating; prove the
      # record is actually accepted end to end.
      model.remove_schema_validations(:prefs, only: :presence)

      expect(model.new(flag: true).valid?).to be(true)
    end

    it "accepts an array of kinds" do
      model.remove_schema_validations(:prefs, only: [:presence])
      model.remove_schema_validations(:flag, only: [:inclusion])

      expect(model.validators_on(:prefs)).to be_empty
      expect(model.validators_on(:flag)).to be_empty
    end

    it "only touches the named column, leaving the other's validator in place" do
      model.remove_schema_validations(:prefs, only: :presence)

      expect(model.validators_on(:flag))
        .to include(an_instance_of(ActiveModel::Validations::InclusionValidator))
    end

    it "is a no-op on a second call (idempotent)" do
      model.remove_schema_validations(:prefs, only: :presence)

      expect { model.remove_schema_validations(:prefs, only: :presence) }
        .not_to(change { model.validators_on(:prefs) }.from([]))
    end

    it "accepts a string column name" do
      model.remove_schema_validations("prefs", only: :presence)

      expect(model.validators_on(:prefs)).to be_empty
    end

    it "raises ArgumentError on an unknown kind" do
      expect { model.remove_schema_validations(:prefs, only: :bogus) }
        .to raise_error(ArgumentError, /unknown validation kind/)
    end
  end
end
