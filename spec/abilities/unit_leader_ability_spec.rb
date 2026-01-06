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

  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "same unit" do
      let(:other_yp) { people(:yp_a_1) }
      let(:other_ul) { people(:ul_a_2) }

      it "can show youth participant in the same unit" do
        is_expected.to be_able_to(:show, other_yp)
      end

      (PERSON_ACTIONS - [:show]).each do |action|
        it "can not #{action} on youth participant in the same unit" do
          is_expected.to_not be_able_to(action, other_yp)
        end
      end

      it "can show unit leader in the same unit" do
        is_expected.to be_able_to(:show, other_ul)
      end

      (PERSON_ACTIONS - [:show]).each do |action|
        it "can not #{action} on other unit leader in the same unit" do
          is_expected.to_not be_able_to(action, other_ul)
        end
      end
    end
  end
end
