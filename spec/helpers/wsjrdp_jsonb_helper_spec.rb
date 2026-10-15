# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# jsonb_accessor's `default:`: what a reader answers for an absent key or a
# stored null, for any cast; not given, false for a boolean and nil else.
describe WsjrdpJsonbHelper do
  let(:model) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "people"
      include WsjrdpJsonbHelper

      jsonb_accessor :jamboree_data, :plain_flag, cast: :boolean
      jsonb_accessor :jamboree_data, :open_flag, cast: :boolean, delete_on_blank: false, default: nil
      jsonb_accessor :jamboree_data, :yes_flag, cast: :boolean, delete_on_blank: false, default: true
      jsonb_accessor :jamboree_data, :plain_text
      jsonb_accessor :jamboree_data, :text_with_default, default: "DE"
      jsonb_accessor :jamboree_data, :day, cast: :date, default: Date.new(2027, 7, 30)
    end
  end

  it "answers the type's default for an absent key when none is given" do
    record = model.new(jamboree_data: {})

    expect(record.plain_flag).to be(false)
    expect(record.plain_text).to be_nil
  end

  it "answers the given default for an absent key or a stored null, never storing it" do
    record = model.new(jamboree_data: {"open_flag" => nil})

    expect(record.open_flag).to be_nil
    expect(record.yes_flag).to be(true)
    expect(record.yes_flag?).to be(true)
    expect(record.text_with_default).to eq("DE")
    expect(record.day).to eq(Date.new(2027, 7, 30))
    expect(record.jamboree_data).to eq("open_flag" => nil)
  end

  it "answers a stored value, false included, over the default" do
    record = model.new(jamboree_data: {})
    record.yes_flag = "0"
    record.text_with_default = "PL"
    record.day = "2027-08-01"

    expect(record.yes_flag).to be(false)
    expect(record.jamboree_data).to include("yes_flag" => false)
    expect(record.text_with_default).to eq("PL")
    expect(record.day).to eq(Date.new(2027, 8, 1))
  end
end
