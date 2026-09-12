# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to AbilityDsl::UserContext: applies the finance cap
# (Wsjrdp2027::FinanceCap) by taking the capped tiers out of the permission
# set. That set is the ONE place the whole rule machinery hangs on --
# Ability#define_instance_side only defines rules for the permissions in
# #all_permissions, and every finance constraint reads the same set -- so a
# tier removed here simply has no rule, everywhere, without any ability class
# knowing about the cap.
#
# The group/layer lookups follow, so no constraint can still find a layer for
# a tier that was taken out. Both are memoized like the core's, and the
# uncapped case costs one array comparison.
module Wsjrdp2027::UserContext
  attr_reader :max_finance_permission

  def initialize(user)
    @max_finance_permission = Wsjrdp2027::FinanceCap.current
    @capped_tiers = Wsjrdp2027::FinanceCap.removed_by(@max_finance_permission)
    super
  end

  def all_permissions
    @uncapped_all_permissions ||= super
    return @uncapped_all_permissions if @capped_tiers.empty?

    @capped_all_permissions ||= @uncapped_all_permissions - @capped_tiers
  end

  # The finance tier in force, and the one the roles alone would grant --
  # both as the tier's permission, :finance_none without any. They differ
  # exactly when the cap changes something, which is what the session bar
  # (layouts/_wsjrdp_session_bar) shows.
  def finance_tier
    Wsjrdp2027::FinanceCap.highest(all_permissions)
  end

  def finance_tier_by_roles
    all_permissions
    Wsjrdp2027::FinanceCap.highest(@uncapped_all_permissions)
  end

  def permission_group_ids(permission)
    @capped_tiers.include?(permission) ? [] : super
  end

  def permission_layer_ids(permission)
    @capped_tiers.include?(permission) ? [] : super
  end
end
