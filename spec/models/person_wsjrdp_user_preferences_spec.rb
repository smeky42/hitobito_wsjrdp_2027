# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Integration of the jsonb_backed_hash facade (Wsjrdp::JsonbBackedHash) on the
# real Person: people.wsjrdp_user_preferences is a backed hash, and the
# wsjrdp_preference_admin_tab jsonb_accessor routes through it, so writes persist
# immediately without a save and without dirtying the record.
describe Person do
  let(:person) { people(:cmt_leader) }

  before { person.update_column(:wsjrdp_user_preferences, {}) }

  # The raw DB value, bypassing the facade.
  def stored(person)
    value = Person.connection.select_value(
      "SELECT wsjrdp_user_preferences FROM people WHERE id = #{person.id}"
    )
    value.is_a?(String) ? JSON.parse(value) : value
  end

  describe "#wsjrdp_user_preferences" do
    it "is a jsonb_backed_hash facade" do
      expect(person.wsjrdp_user_preferences).to be_a(Wsjrdp::JsonbBackedHash)
    end

    it "persists a per-key write immediately, without save or dirtying the record" do
      person.wsjrdp_user_preferences[:foo] = "bar"

      expect(stored(person)).to eq("foo" => "bar")
      expect(person.wsjrdp_user_preferences[:foo]).to eq("bar")
      expect(person).not_to be_changed
    end

    it "deletes a key on nil" do
      person.wsjrdp_user_preferences[:foo] = "bar"
      person.wsjrdp_user_preferences[:foo] = nil

      expect(person.wsjrdp_user_preferences.key?("foo")).to be(false)
      expect(stored(person)).to eq({})
    end
  end

  describe "#wsjrdp_preference_admin_tab (jsonb_accessor routed through the facade)" do
    it "persists immediately on assignment, under the admin_tab key" do
      person.wsjrdp_preference_admin_tab = "always"

      expect(stored(person)).to eq("admin_tab" => "always")
      expect(person.wsjrdp_preference_admin_tab).to eq("always")
      expect(person.wsjrdp_user_preferences["admin_tab"]).to eq("always")
      expect(person).not_to be_changed
    end

    it "clears the key immediately on a blank value (delete_on_blank)" do
      person.wsjrdp_preference_admin_tab = "always"
      person.wsjrdp_preference_admin_tab = ""

      expect(person.wsjrdp_preference_admin_tab).to be_nil
      expect(stored(person)).to eq({})
    end

    it "is visible on a freshly loaded record" do
      person.wsjrdp_preference_admin_tab = "ondemand"

      expect(Person.find(person.id).wsjrdp_preference_admin_tab).to eq("ondemand")
    end
  end

  # Which sections of a person's Abmeldung page stand open, kept for whoever is
  # logged in -- the same facade, under its own key, as a list.
  describe "#wsjrdp_preference_deregistration_open_sections" do
    it "persists the list immediately, under the deregistration_open_sections key" do
      person.wsjrdp_preference_deregistration_open_sections = %w[capture receipt]

      expect(stored(person)).to eq("deregistration_open_sections" => %w[capture receipt])
      expect(person.wsjrdp_user_preferences["deregistration_open_sections"]).to eq(%w[capture receipt])
      expect(person).not_to be_changed
    end

    # Everything closed is a state of its own, not the absence of one.
    it "keeps an empty list" do
      person.wsjrdp_preference_deregistration_open_sections = []

      expect(stored(person)).to eq("deregistration_open_sections" => [])
    end
  end

  describe "attribute wiring" do
    it "is registered internal-only: used, paper-trail-skipped, not public" do
      expect(Person.used_attributes).to include(:wsjrdp_user_preferences)
      expect(Person.paper_trail_options[:skip]).to include("wsjrdp_user_preferences")
      expect(Person::PUBLIC_ATTRS).not_to include(:wsjrdp_user_preferences)
    end
  end
end
