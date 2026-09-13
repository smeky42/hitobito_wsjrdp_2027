# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to ApplicationController: the wagon's session settings --
# the finance cap (Wsjrdp2027::FinanceCap) and the two flags that say
# what the session UI (layouts/_wsjrdp_session_bar) shows -- set
# through query parameters and kept in the session.
#
#   ?max_finance_permission=finance_read   this session works at the read tier
#   ?max_finance_permission=               (or any unknown value) drops the
#                                          pick, so the default tier applies
#   ?finance_tier_bar=always|hidden|ondemand
#                                          when the yellow session bar shows:
#                                          always; never; or -- the default --
#                                          while the cap lowers the tier or a
#                                          cap is set at all (the bar's own x
#                                          switches to this)
#   ?admin_tab=always|ondemand|hidden      when the admin tab shows: always;
#                                          while one of the bars is missing;
#                                          or never -- which is also what an
#                                          unset or unknown value means. A
#                                          truthy spelling (1, true, on, yes)
#                                          counts as always, a falsy one
#                                          (0, false, off, no) as hidden.
#                                          Unlike the other two it is also kept
#                                          per login user in
#                                          person.wsjrdp_user_preferences,
#                                          so it survives the login.
#
# The cap and the bar live only in the session -- server-side, gone
# with the login. admin_tab additionally mirrors the login user's
# persisted preference: a fresh session is seeded from it, and a
# change writes the normalised value back (see #store_admin_tab). All
# are validated on every read: a stale or unknown value is dropped and
# counts as no cap / as ondemand / as no tab. The cap is applied
# wherever the current ability is built, so a capped person sees the
# same reduced rights on /fin and on a person's finance tab.
#
# Ordering: the parameters are stored in a prepend_before_action,
# i.e. before anything in the chain can have built #current_ability;
# the memo is reset anyway, so a cap set on this very request already
# applies to it.
module Wsjrdp2027::Concerns::SessionSettings
  extend ActiveSupport::Concern

  SESSION_KEY = :max_finance_permission
  FINANCE_TIER_BAR_KEY = :finance_tier_bar
  FINANCE_TIER_BAR_MODES = %w[always hidden ondemand].freeze
  ADMIN_TAB_KEY = :admin_tab
  ADMIN_TAB_MODES = %w[always ondemand hidden].freeze
  # Spellings of "yes" and "no" that a hand-typed URL is likely to carry.
  TAB_ALWAYS = %w[1 true on yes].freeze
  TAB_HIDDEN = %w[0 false off no].freeze

  prepended do
    prepend_before_action :store_session_settings
    helper_method :max_finance_permission, :finance_tier_bar, :admin_tab
  end

  def current_ability
    @current_ability ||= if current_person
      Ability.new(current_person, max_finance_permission: max_finance_permission)
    else
      super
    end
  end

  # The tier picked for this session as a symbol, nil without a pick.
  # Validated on the way out, and a value that cannot be honoured is
  # removed: an unknown one -- an older deploy's, a hand-edited one --
  # and one above what the person's roles grant, which a role change
  # can leave behind. Both then count as no pick, so the default tier
  # applies and the bar goes quiet again.
  def max_finance_permission
    value = session[SESSION_KEY]
    return nil if value.nil?

    if Wsjrdp2027::FinanceCap.valid?(value) &&
        !Wsjrdp2027::FinanceCap.exceeds?(value, current_person)
      return value.to_sym
    end

    session.delete(SESSION_KEY)
    nil
  end

  # The session bar's mode as a symbol; :ondemand unless set to something
  # valid, a stale value removed on the way.
  def finance_tier_bar
    valid_session_mode(FINANCE_TIER_BAR_KEY, FINANCE_TIER_BAR_MODES) || :ondemand
  end

  # The admin tab's mode as a symbol: :always, :ondemand, or :hidden,
  # which is also what an unset or stale value means (and a stale one
  # is removed on the way). The session only ever holds one of the
  # three words, the truthy and falsy spellings are resolved on the
  # way in.
  def admin_tab
    valid_session_mode(ADMIN_TAB_KEY, ADMIN_TAB_MODES) || :hidden
  end

  private

  def valid_session_mode(key, modes)
    value = session[key].to_s
    return value.to_sym if modes.include?(value)

    session.delete(key) if session.key?(key)
    nil
  end

  def valid_finance_cap_value(value)
    return if value.nil?
    value = value.to_s
    Wsjrdp2027::FinanceCap.valid?(value) ? value : nil
  end

  def valid_finance_tier_bar_value(value)
    return if value.nil?
    value = value.to_s
    FINANCE_TIER_BAR_MODES.include?(value) ? value : nil
  end

  def valid_tab_mode_value(value)
    value = value.to_s
    return "always" if TAB_ALWAYS.include?(value.downcase)
    return "hidden" if TAB_HIDDEN.include?(value.downcase)
    value if ADMIN_TAB_MODES.include?(value)
  end

  def store_or_clear_session_param(key, value)
    if value.nil?
      session.delete(key)
    else
      session[key] = value
    end
  end

  def store_session_settings
    if params.key?(SESSION_KEY)
      store_or_clear_session_param(SESSION_KEY, valid_finance_cap_value(params[SESSION_KEY]))
      @current_ability = nil
    end
    if params.key?(FINANCE_TIER_BAR_KEY)
      store_or_clear_session_param(FINANCE_TIER_BAR_KEY, valid_finance_tier_bar_value(params[FINANCE_TIER_BAR_KEY]))
    end
    store_admin_tab_session_setting
  end

  # admin_tab is mirrored between the session and the login user's
  # persisted preference. `?admin_tab=` carries either a normalised
  # value or an explicit blank (= reset); both are written to the
  # session, and the persisted preference is updated only when the
  # value actually changed vs. what the session held before (a blank
  # clears both). An unknown, non-blank value is ignored. Without the
  # parameter a fresh session (e.g. right after login) is seeded from
  # the persisted preference. Nothing happens without a login user.
  def store_admin_tab_session_setting
    return unless login_person

    if params.key?(ADMIN_TAB_KEY)
      raw = params[ADMIN_TAB_KEY].to_s
      mode = valid_tab_mode_value(raw)
      if mode || raw.blank?  # ignore non-blank, invalid values
        previous = session[ADMIN_TAB_KEY]
        store_or_clear_session_param(ADMIN_TAB_KEY, mode)
        login_person.wsjrdp_user_preferences[ADMIN_TAB_KEY] = mode if mode != previous
      end
    elsif !session.key?(ADMIN_TAB_KEY)
      seed = valid_tab_mode_value(login_person.wsjrdp_user_preferences[ADMIN_TAB_KEY])
      session[ADMIN_TAB_KEY] = seed unless seed.nil?
    end
  end

  # The person who actually logged in, never a currently impersonated
  # one (during impersonation current_person is the impersonated user
  # and origin_user the real one). Memoised so origin_user's lookup
  # runs once and the seed read and the persist write share the same
  # object.
  def login_person
    return @login_person if defined?(@login_person)

    @login_person = origin_user || current_person
  end
end
