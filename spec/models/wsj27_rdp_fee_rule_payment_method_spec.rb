# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The payment method of an installment plan goes with the plan: present exactly
# when a plan is, direct debit unless chosen otherwise -- on the fee rule, the
# person and the standard plans alike (the database checks the same).
describe "installment plan payment method" do
  let(:person) { people(:yp_a_1) }

  def rule(owner: person, **attrs)
    Wsj27RdpFeeRule.create!(people_id: owner.id, status: "planned", **attrs)
  end

  describe Wsj27RdpFeeRule do
    it "is direct debit for a plan without one" do
      expect(rule(custom_installments_string: "2026: 100; 100").custom_installments_payment_method)
        .to eq("direct_debit")
    end

    it "keeps a chosen one" do
      expect(rule(custom_installments_string: "2026: 100", custom_installments_payment_method: "credit_transfer")
        .custom_installments_payment_method).to eq("credit_transfer")
    end

    it "is nil without a plan, and is dropped with the plan" do
      expect(rule(custom_installments_issue: "HELP-1", custom_installments_payment_method: "credit_transfer")
        .custom_installments_payment_method).to be_nil

      with_plan = rule(owner: people(:yp_a_2), custom_installments_string: "2026: 100",
        custom_installments_payment_method: "credit_transfer")
      with_plan.update!(custom_installments_string: "keine")
      expect(with_plan.reload.custom_installments_payment_method).to be_nil
    end

    it "is checked by the database" do
      fee_rule = rule(custom_installments_string: "2026: 100")

      expect { fee_rule.update_columns(custom_installments_payment_method: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /payment_method_iff_plan/)
    end
  end

  describe "on the status form" do
    it "creates no planned rule for a payment method alone" do
      person.planned_custom_installments_payment_method = "direct_debit"

      expect { person.save! }.not_to change { Wsj27RdpFeeRule.count }
    end

    it "stores the chosen payment method with a planned plan" do
      person.planned_custom_installments_string = "2026: 100"
      person.planned_custom_installments_payment_method = "credit_transfer"
      person.save!

      expect(Wsj27RdpFeeRule.find_by(people_id: person.id, status: "planned"))
        .to have_attributes(custom_installments_payment_method: "credit_transfer")
    end
  end

  describe Person do
    it "is direct debit for a plan without one and nil without a plan" do
      person.update!(wsjrdp_raw_installments_eur: [2026, 100])
      expect(person.reload.wsjrdp_installments_payment_method).to eq("direct_debit")

      person.update!(wsjrdp_raw_installments_eur: nil)
      expect(person.reload.wsjrdp_installments_payment_method).to be_nil
    end

    it "refuses a payment method without a plan in the database" do
      expect { person.update_columns(wsjrdp_installments_payment_method: "direct_debit") }
        .to raise_error(ActiveRecord::StatementInvalid, /payment_method_iff_plan/)
    end
  end

  describe WsjrdpPaymentPlan do
    def plan(**attrs)
      WsjrdpPaymentPlan.create!(wsjrdp_role: "TEST", single_payment: false, installments_string: "2026: 100", **attrs)
    end

    it "is direct debit unless chosen otherwise" do
      expect(plan).to have_attributes(payment_method: "direct_debit", payment_method_display: "Lastschrift")
    end

    it "is soft-deleted only: destroy sets deleted_at, a deleted plan is read-only, delete refuses" do
      standard = plan

      expect { standard.destroy }.not_to change { WsjrdpPaymentPlan.count }
      expect(standard.reload.deleted_at).to be_present
      expect(WsjrdpPaymentPlan.kept).not_to include(standard)
      expect { standard.update!(comment: "x") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { plan.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses deleting a plan a person refers to, in the database" do
      standard = plan
      person.update_columns(wsjrdp_installments_payment_plan_id: standard.id)

      expect { WsjrdpPaymentPlan.where(id: standard.id).delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "keeps one plan in effect per role, single payment and payment method" do
      deleted = plan.tap(&:destroy)

      expect { plan(payment_method: "credit_transfer") }.not_to raise_error
      expect { plan }.not_to raise_error
      expect { plan }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(deleted.reload).to be_deleted
    end

    it "always is either for single payment or for installments" do
      expect { plan(single_payment: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
