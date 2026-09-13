# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Exercises the facade against a throwaway table with an anonymous model, so the
# behaviour is verified in isolation from any real model. The table is created
# once for the group and dropped afterwards; the per-example transaction rolls
# back the rows.
describe Wsjrdp::JsonbBackedHash do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ActiveRecord::Base.connection.create_table(:jbh_specs, force: true) do |t|
      t.jsonb :prefs, null: false, default: {}
      t.string :name
      t.timestamps
    end
    @model = Class.new(ActiveRecord::Base) do
      self.table_name = "jbh_specs"
      include WsjrdpJsonbHelper
      jsonb_backed_hash :prefs
      jsonb_accessor :prefs, :tab, prefix: :pref
      def self.name = "JbhSpec"
    end
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    ActiveRecord::Base.connection.drop_table(:jbh_specs, if_exists: true)
  end

  let(:model) { @model }
  let(:record) { model.create!(name: "r") }

  before { model.delete_all }

  # The raw DB value, bypassing the facade.
  def stored(record)
    value = model.connection.select_value("SELECT prefs FROM jbh_specs WHERE id = #{record.id}")
    value.is_a?(String) ? JSON.parse(value) : value
  end

  it "returns a facade, not the raw hash" do
    expect(record.prefs).to be_a(described_class)
  end

  describe "per-key writes on a persisted record" do
    it "persists immediately without save" do
      record.prefs[:a] = 1
      expect(stored(record)).to eq("a" => 1)
      expect(record.prefs[:a]).to eq(1)
    end

    it "does not leave the column dirty, so a later save cannot clobber it" do
      record.prefs[:a] = 1
      expect(record.changes).not_to have_key("prefs")
      expect(record).not_to be_changed
    end

    it "does not bump updated_at" do
      record.update_column(:updated_at, 1.year.ago)
      before = model.connection.select_value("SELECT updated_at FROM jbh_specs WHERE id = #{record.id}")
      record.prefs[:a] = 1
      after = model.connection.select_value("SELECT updated_at FROM jbh_specs WHERE id = #{record.id}")
      expect(after).to eq(before)
    end

    it "merges independent keys instead of clobbering the whole column" do
      record.prefs[:a] = 1
      model.connection.execute("UPDATE jbh_specs SET prefs = jsonb_set(prefs, '{b}', '2') WHERE id = #{record.id}")
      record.prefs[:c] = 3
      expect(stored(record)).to eq("a" => 1, "b" => 2, "c" => 3)
    end
  end

  describe "deleting" do
    it "removes a key when assigned nil" do
      record.prefs[:a] = 1
      record.prefs[:a] = nil
      expect(record.prefs.key?("a")).to be(false)
      expect(stored(record)).to eq({})
    end

    it "keeps false as a real value" do
      record.prefs[:flag] = false
      expect(record.prefs[:flag]).to be(false)
      expect(stored(record)).to eq("flag" => false)
    end

    it "#delete removes the key and returns the old value" do
      record.prefs[:a] = 1
      expect(record.prefs.delete(:a)).to eq(1)
      expect(record.prefs).to be_empty
      expect(stored(record)).to eq({})
    end

    it "#clear empties the whole column" do
      record.prefs[:a] = 1
      record.prefs[:b] = 2
      record.prefs.clear
      expect(record.prefs).to be_empty
      expect(stored(record)).to eq({})
    end
  end

  describe "indifferent keys" do
    it "treats a symbol and a string as the same string key" do
      record.prefs[:a] = 1
      expect(record.prefs["a"]).to eq(1)
      record.prefs["a"] = 2
      expect(record.prefs[:a]).to eq(2)
      expect(stored(record).keys).to eq(["a"])
    end
  end

  describe "whole-hash setter (column=)" do
    it "replaces the whole column immediately and stays non-dirty" do
      record.prefs[:old] = 1
      record.prefs = {only: "this"}
      expect(record.prefs.to_h).to eq("only" => "this")
      expect(stored(record)).to eq("only" => "this")
      expect(record.changes).not_to have_key("prefs")
    end

    it "treats nil as an empty hash" do
      record.prefs[:a] = 1
      record.prefs = nil
      expect(record.prefs).to be_empty
      expect(stored(record)).to eq({})
    end
  end

  describe "a new (unpersisted) record" do
    it "buffers writes and persists them with the INSERT" do
      r = model.new(name: "n")
      r.prefs[:a] = 1
      expect(r.prefs[:a]).to eq(1)
      expect(model.count).to eq(0)
      r.save!
      expect(stored(r)).to eq("a" => 1)
    end

    it "switches to immediate writes once persisted" do
      r = model.create!(name: "n", prefs: {a: 1})
      r.prefs[:b] = 2
      expect(stored(r)).to eq("a" => 1, "b" => 2)
    end
  end

  describe "a record loaded without the column (reduced select)" do
    it "lazily fetches the value on demand" do
      record.prefs[:k] = "v"
      reduced = model.select(:id).find(record.id)
      expect(reduced.has_attribute?(:prefs)).to be(false)
      expect(reduced.prefs[:k]).to eq("v")
      expect(reduced.prefs.to_h).to eq("k" => "v")
    end
  end

  describe "transaction safety (read-through)" do
    it "does not leave a rolled-back write readable" do
      record.prefs[:base] = 1
      model.transaction(requires_new: true) do
        record.prefs[:t] = 99
        expect(record.prefs[:t]).to eq(99) # visible inside the transaction
        raise ActiveRecord::Rollback
      end
      expect(record.prefs.key?("t")).to be(false)
      expect(stored(record)).to eq("base" => 1)
    end
  end

  describe "a jsonb_accessor on the same column" do
    it "writes the accessor's key immediately through the facade" do
      record.pref_tab = "always"
      expect(stored(record)).to eq("tab" => "always")
      expect(record.pref_tab).to eq("always")
      expect(record.prefs["tab"]).to eq("always")
    end

    it "deletes the key on a blank value (delete_on_blank) immediately" do
      record.pref_tab = "always"
      record.pref_tab = ""
      expect(record.prefs.key?("tab")).to be(false)
      expect(stored(record)).to eq({})
    end
  end
end
