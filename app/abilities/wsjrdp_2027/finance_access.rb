# frozen_string_literal: true

# Shared ability constraints for the three finance tiers :finance_read
# (see), :finance (edit) and :finance_admin.  Included into the core
# ability classes by Wsjrdp2027::VariousAbility (all finance models)
# and Wsjrdp2027::PersonAbility (:fin_admin on people); covered by
# spec/abilities/finance_ability_spec.rb.
#
# The tiers are CUMULATIVE: whoever may edit may also read, whoever
# may administer may do both.
#
# Deliberately NOT bound to the root layer. Two legitimate role
# placements would otherwise be locked out:
#   * Group::Extern::FinanceAuditor holds :finance_read on the EXTERN
#     layer,
#   * a Group::Root::Finance role in a NESTED Group::Root ("CMT
#     Warteliste") holds :finance on that nested layer, not on the
#     root one.
# Holding the permission at all is therefore the criterion. That is
# safe because every role granting a finance tier sets
# admin_only_assignment, so only CMT admins can hand them out in the
# first place.
module Wsjrdp2027::FinanceAccess
  FINANCE_TIERS = %i[finance_read finance finance_admin].freeze
  WRITING_TIERS = %i[finance finance_admin].freeze

  def if_finance_read
    finance_tiers.any?
  end

  def if_finance_write
    finance_tiers.any? { |tier| WRITING_TIERS.include?(tier) }
  end

  def if_finance_admin
    finance_tiers.include?(:finance_admin)
  end

  private

  def finance_tiers
    user_context.all_permissions & FINANCE_TIERS
  end
end
