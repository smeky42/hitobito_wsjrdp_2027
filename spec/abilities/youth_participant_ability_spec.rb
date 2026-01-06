require "spec_helper"

describe PersonAbility do
  PERSON_ACTIONS = %i[
    show
    show_details
    show_full

    update
    update_email
    update_password
    update_settings

    security
    send_password_instructions
    totp_disable
    totp_reset

    create_invoice
    index_invoices
    fin_admin

    history
    log

    approve_add_request
    destroy
    impersonate_user
    index_notes
    index_tags
    manage_tags
    primary_group
  ]

  context "youth participant" do
    let(:yp) { people(:yp_a_1) }

    subject { Ability.new(yp.reload) }

    context "same unit" do
      let(:other_yp) { people(:yp_a_2) }
      let(:other_ul) { people(:ul_a_1) }

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on other youth participant in the same unit" do
          is_expected.to_not be_able_to(action, other_yp)
        end
      end

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on unit leader in the same unit" do
          is_expected.to_not be_able_to(action, other_ul)
        end
      end
    end

    context "different unit" do
      let(:other_yp) { people(:yp_b_1) }
      let(:other_ul) { people(:ul_b_1) }

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on youth participant in different unit" do
          is_expected.to_not be_able_to(action, other_yp)
        end
      end

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on unit leader in different unit" do
          is_expected.to_not be_able_to(action, other_ul)
        end
      end
    end

    context "CMT" do
      let(:cmt) { people(:cmt_member1) }

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on CMT member" do
          is_expected.to_not be_able_to(action, cmt)
        end
      end
    end

    context "IST" do
      let(:ist) { people(:ist_a_1) }

      PERSON_ACTIONS.each do |action|
        it "can not #{action} on IST member" do
          is_expected.to_not be_able_to(action, ist)
        end
      end
    end
  end
end
