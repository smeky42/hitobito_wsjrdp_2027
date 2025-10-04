# frozen_string_literal: true

require "spec_helper"

describe Wizards::Steps::NewUserForm do
  describe "YP validations" do
    let(:group) { groups(:empty_unit) }
    let(:wizard) { Wizards::RegisterNewUserWizard.new(group: group) }

    subject(:form) { described_class.new(wizard) }

    before do
      group.self_registration_role_type = "Group::Unit::Member"
    end

    describe "birthday" do
      before do
        form.first_name = "Youth"
        form.last_name = "Participant"
        form.email = "youth@participant.de"
      end

      it "is invalid when YP is too old" do
        form.birthday = Date.new(2000, 1, 1)
        expect(form).to be_invalid
      end

      it "is valid when YP is of correct age" do
        form.birthday = Date.new(2011, 1, 1)
        expect(form).to be_valid
      end

      it "is invalid when YP is too young" do
        form.birthday = Date.new(2020, 1, 1)
        expect(form).to be_invalid
      end

      # From bulletin: "born after 30 July 2009 but not later than 30 July 2013"
      edge_case_allowed = {
        Date.new(2009, 7, 29) => false,
        Date.new(2009, 7, 30) => false,
        Date.new(2009, 7, 31) => true,
        Date.new(2013, 7, 29) => true,
        Date.new(2013, 7, 30) => true,
        Date.new(2013, 7, 31) => false
      }
      edge_case_allowed.each do |date, expected|
        it "is #{expected ? "valid" : "invalid"} when YP is born on #{date}" do
          form.birthday = date
          expect(form).to(expected ? be_valid : be_invalid)
        end
      end
    end
  end
end
