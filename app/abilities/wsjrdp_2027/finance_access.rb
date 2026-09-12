# frozen_string_literal: true

# Shared ability constraints for the finance tiers.
#
# The tiers are CUMULATIVE: whoever may edit may also read, whoever
# may administer may do both.
#
# :finance_audit sits between read and edit and is still READ-ONLY.
#
# Deliberately NOT bound to the root layer. Two legitimate role
# placements would otherwise be locked out:
#   * Group::Extern::FinanceAuditor holds :finance_read on the EXTERN
#     layer,
#   * a Group::Root::Finance role in a NESTED Group::Root holds
#     :finance on that nested layer, not on the root one.
# Holding the permission at all is therefore the criterion. That is
# safe because every role granting a finance tier sets
# admin_only_assignment, so only CMT admins can hand them out in the
# first place.
module Wsjrdp2027::FinanceAccess
  FINANCE_TIERS = %i[finance_read finance_audit finance finance_manage].freeze
  WRITING_TIERS = %i[finance finance_manage].freeze

  def if_finance_read
    finance_tiers.any?
  end

  def if_finance_audit
    finance_tiers.include?(:finance_audit)
  end

  def if_finance_write
    finance_tiers.any? { |tier| WRITING_TIERS.include?(tier) }
  end

  # The ability action this tier guards is still called :fin_admin -- the
  # name predates the split into tiers.
  def if_finance_manage
    finance_tiers.include?(:finance_manage)
  end

  private

  def finance_tiers
    user_context.all_permissions & FINANCE_TIERS
  end
end
