# frozen_string_literal: true

# Shared ability constraint: the user holds the :finance permission on the
# root layer (the contingent). Included into the core ability classes by
# Wsjrdp2027::VariousAbility (all finance models) and
# Wsjrdp2027::PersonAbility (:fin_admin on people); covered by
# spec/abilities/finance_ability_spec.rb.
module Wsjrdp2027::FinanceOnRoot
  def if_finance_on_root
    user_context.permission_layer_ids(:finance).include?(Group.root.id)
  end
end
