# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Who the mail with the Abmelde-Formular comes from and who gets it in Bcc:
# a youth participant's and a unit leader's unit, the last unit after a move
# to a waiting list, the primary group without any unit, and the helpdesk
# where a ticket is entered.
describe Wsjrdp2027::DeregistrationMailRecipients do
  let(:yp) { people(:yp_a_1) }
  let(:unit_a) { groups(:unit_a) }
  let(:waiting_list) { groups(:empty_unit) }
  let(:unit_a_bcc) { %w[unit-manager@worldscoutjamboree.de head-of-finance@worldscoutjamboree.de] }
  let(:waiting_list_bcc) { %w[waiting@worldscoutjamboree.de] }

  before do
    unit_a.update_columns(additional_info: {"unit_code" => "#8B0000", "support_cmt_mail_addresses" => unit_a_bcc})
    waiting_list.update_columns(name: "YP Warteliste",
      additional_info: {"support_cmt_mail_addresses" => waiting_list_bcc})
  end

  def recipients(person) = described_class.new(person.reload)

  # The person's roles in the unit end, a role on the waiting list begins.
  def move_to_waiting_list(person)
    person.roles.each { |role| role.update_columns(start_on: Date.new(2025, 9, 1), end_on: Date.yesterday) }
    Group::Unit::Member.create!(person: person, group: waiting_list, start_on: Date.current)
    person.update_columns(primary_group_id: waiting_list.id)
  end

  it "takes a youth participant's Bcc from the unit" do
    r = recipients(yp)

    expect(r.unit_group).to eq(unit_a)
    expect(r.unit_source).to eq("unit")
    expect(r.bcc).to eq(unit_a_bcc)
    expect(r.from).to eq("unit-management@worldscoutjamboree.de")
  end

  it "takes the last unit for a person on a waiting list" do
    move_to_waiting_list(yp)

    r = recipients(yp)

    expect(r.unit_group).to eq(unit_a)
    expect(r.unit_source).to eq("last_unit")
    expect(r.bcc).to eq(unit_a_bcc)
  end

  it "takes the primary group for a person never in a unit" do
    unit_a.update_columns(additional_info: {"support_cmt_mail_addresses" => unit_a_bcc})
    move_to_waiting_list(yp)

    r = recipients(yp)

    expect(r.unit_group).to eq(waiting_list)
    expect(r.unit_source).to eq("primary_group")
    expect(r.bcc).to eq(waiting_list_bcc)
  end

  it "adds the helpdesk where a ticket is entered, each address once" do
    yp.update!(deregistration_issue: "HELP-123")

    expect(recipients(yp).bcc).to eq(unit_a_bcc + ["unit-management@worldscoutjamboree.de"])
  end

  it "takes the role the form was made with" do
    yp.update!(deregistration_person_role: "IST")

    r = recipients(yp)

    expect(r.unit_group).to be_nil
    expect(r.from).to eq("ist@worldscoutjamboree.de")
  end

  it "gives an IST no unit's addresses, the helpdesk only with a ticket" do
    ist = people(:ist_a_1)
    expect(recipients(ist).bcc).to eq([])
    expect(recipients(ist).as_json).to eq("from" => "ist@worldscoutjamboree.de", "to" => [ist.email],
      "cc" => [], "bcc" => [], "reply_to" => [], "unit" => nil)

    ist.update!(deregistration_issue: "HELP-9")
    expect(recipients(ist).bcc).to eq(["ist@worldscoutjamboree.de"])
  end

  describe "to and cc" do
    it "sends a youth participant's mail to the person, the guardians and the extra addresses in Cc" do
      yp.update_columns(additional_contact_email_a: "a@example.org", additional_contact_email_b: "b@example.org",
        additional_contact_single: false)
      yp.additional_emails.create!(email: "extra@example.org", label: "Privat", mailings: true)
      yp.additional_emails.create!(email: "quiet@example.org", label: "Arbeit", mailings: false)

      r = recipients(yp)

      expect(r.to).to eq([yp.email])
      expect(r.cc).to eq(%w[a@example.org b@example.org extra@example.org])
    end

    it "names only the first guardian where one signs alone, and none twice" do
      yp.update_columns(additional_contact_email_a: yp.email, additional_contact_email_b: "b@example.org",
        additional_contact_single: true)

      expect(recipients(yp).cc).to eq([])
    end

    it "adds the contingent address of a unit leader, and no guardians of an adult" do
      ul = people(:ul_a_1)
      ul.update_columns(birthday: Date.new(1990, 1, 1), additional_contact_email_a: "a@example.org")
      ul.update!(wsjrdp_email: "ul@units.worldscoutjamboree.de")

      r = recipients(ul)

      expect(r.to).to eq([ul.email, "ul@units.worldscoutjamboree.de"])
      expect(r.cc).to eq([])
    end
  end

  it "answers the unit as the JSON names it" do
    move_to_waiting_list(yp)

    expect(recipients(yp).as_json["unit"])
      .to eq("group_id" => unit_a.id, "name" => unit_a.name, "source" => "last_unit")
  end
end
