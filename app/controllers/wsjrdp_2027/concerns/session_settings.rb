# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to ApplicationController: the wagon's session settings -- the
# finance cap (Wsjrdp2027::FinanceCap) and the two flags that say what the
# session UI (layouts/_wsjrdp_session_bar) shows -- set through query
# parameters and kept in the session.
#
#   ?max_finance_permission=finance_read   caps this session at the read tier
#   ?max_finance_permission=               (or any unknown value) lifts the cap
#   ?finance_tier_bar=always|hidden|ondemand
#                                          when the yellow session bar shows:
#                                          always; never; or -- the default --
#                                          while the cap lowers the tier or a
#                                          cap is set at all (the bar's own x
#                                          switches to this)
#   ?compact_admin_tab=always|ondemand     when the admin tab shows: always;
#                                          or while one of the bars is
#                                          missing. Not set (the default, and
#                                          any unknown value): never.
#
# All three live in the session -- server-side, gone with the login -- and
# are validated on every read: a stale or unknown value is dropped and counts
# as no cap / as demand / as no tab. The cap is applied wherever the current
# ability is built, so a capped person sees the same reduced rights on /fin
# and on a person's finance tab.
#
# Ordering: the parameters are stored in a prepend_before_action, i.e. before
# anything in the chain can have built #current_ability; the memo is reset
# anyway, so a cap set on this very request already applies to it.
module Wsjrdp2027::Concerns::SessionSettings
  extend ActiveSupport::Concern

  SESSION_KEY = :max_finance_permission
  BAR_KEY = :finance_tier_bar
  BAR_MODES = %w[always hidden ondemand].freeze
  TAB_KEY = :compact_admin_tab
  TAB_MODES = %w[always ondemand].freeze

  prepended do
    prepend_before_action :store_session_settings
    helper_method :max_finance_permission, :finance_tier_bar, :compact_admin_tab
  end

  def current_ability
    @current_ability ||= if current_person
      Ability.new(current_person, max_finance_permission: max_finance_permission)
    else
      super
    end
  end

  # The cap of this session as a tier symbol, nil for none. Validated on the
  # way out: an unknown value -- an older deploy's, a hand-edited one -- is
  # removed and treated as if it had never been set.
  def max_finance_permission
    value = session[SESSION_KEY]
    return nil if value.nil?
    return value.to_sym if Wsjrdp2027::FinanceCap.valid?(value)

    session.delete(SESSION_KEY)
    nil
  end

  # The session bar's mode as a symbol; :ondemand unless set to something
  # valid, a stale value removed on the way.
  def finance_tier_bar
    valid_session_mode(BAR_KEY, BAR_MODES) || :ondemand
  end

  # The admin tab's mode as a symbol -- :always or :ondemand -- or nil, which
  # means no tab; a stale value is removed on the way.
  def compact_admin_tab
    valid_session_mode(TAB_KEY, TAB_MODES)
  end

  private

  def valid_session_mode(key, modes)
    value = session[key].to_s
    return value.to_sym if modes.include?(value)

    session.delete(key) if session.key?(key)
    nil
  end

  def store_session_settings
    if params.key?(SESSION_KEY)
      store_session_param(SESSION_KEY) { |value| Wsjrdp2027::FinanceCap.valid?(value) }
      @current_ability = nil
    end
    store_session_param(BAR_KEY) { |value| BAR_MODES.include?(value) } if params.key?(BAR_KEY)
    store_session_param(TAB_KEY) { |value| TAB_MODES.include?(value) } if params.key?(TAB_KEY)
  end

  # A valid value lands in the session, anything else clears the key -- so
  # an empty parameter is the way to unset it.
  def store_session_param(key)
    value = params[key].to_s
    if yield(value)
      session[key] = value
    else
      session.delete(key)
    end
  end
end
