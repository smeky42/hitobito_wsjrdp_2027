# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# additional_info on fee rules and standard plans: jsonb, {} by default, never
# NULL -- an empty {} is valid, nil stands for {}.
describe "additional_info on fee rules and standard plans" do
  let(:person) { people(:yp_a_1) }

  {
    Wsj27RdpFeeRule => -> { {people_id: people(:yp_a_1).id, status: "planned"} },
    WsjrdpPaymentPlan => -> { {wsjrdp_role: "TEST", single_payment: false, installments_string: "2026: 100"} }
  }.each do |model, attrs|
    describe model do
      it "is {} by default and valid" do
        record = model.create!(instance_exec(&attrs))

        expect(record.reload.additional_info).to eq({})
      end

      it "stores what is set, and {} for nil" do
        record = model.create!(**instance_exec(&attrs), additional_info: {"key" => "value"})
        expect(record.reload.additional_info).to eq("key" => "value")

        record.update!(additional_info: nil)
        expect(record.reload.additional_info).to eq({})
      end

      it "is never NULL in the database" do
        record = model.create!(instance_exec(&attrs))

        expect { record.update_columns(additional_info: nil) }.to raise_error(ActiveRecord::NotNullViolation)
      end
    end
  end
end
