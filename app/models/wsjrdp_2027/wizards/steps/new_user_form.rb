# frozen_string_literal: true

module Wsjrdp2027::Wizards::Steps::NewUserForm
  extend ActiveSupport::Concern

  include BuddyIdHelper

  included do
    attribute :birthday, :date
    attribute :buddy_id, :string

    validates :email, :birthday, presence: true
    validate :assert_role_policy
    validate :assert_age_policy
  end

  def initialize(wizard, **params)
    params[:buddy_id] ||= get_random_spice
    params[:birthday] ||= Date.new(2009, 7, 31)
    super
  end

  def assert_role_policy
    unless wizard.role.type.in?(["Group::Unit::Member", "Group::Unit::UnapprovedLeader", "Group::Ist::Member", "Group::Root::Member"])
      message = I18n.t("groups.self_registration.create.flash.role_policy")
      errors.add(:base, message)
    end
  end

  def assert_age_policy
    if birthday.nil?
      message = I18n.t("groups.self_registration.create.flash.birthday_format")
      errors.add(:base, message)
      return
    end

    # Youth Particpants: born after 30 July 2009 but not later than 30 July 2013
    if birthday > Date.new(2013, 7, 30)
      message = I18n.t("groups.self_registration.create.flash.to_young")
      errors.add(:base, message)
    end

    # Check that YPs are born before 30 July 2009
    # From Bulletin 1 / Circular 01:
    # "Youth Participants must be between the ages of 14 and 17 at the
    #  time of the event (born after 30 July 2009 but not later than
    #  30 July 2013)."
    if (wizard.role.type == "Group::Unit::Member") && birthday <= Date.new(2009, 7, 30)
      message = I18n.t("groups.self_registration.create.flash.yp_to_old")
      errors.add(:base, message)
    end

    # Adults: born on or before 30 July 2009
    if (wizard.role.type == "Group::Unit::UnapprovedLeader") && birthday > 18.years.ago.to_date
      message = I18n.t("groups.self_registration.create.flash.ul_to_young")
      errors.add(:base, message)
    end

    if (wizard.role.type == "Group::Ist::Member") && birthday > Date.new(2009, 7, 30)
      message = I18n.t("groups.self_registration.create.flash.ist_to_young")
      errors.add(:base, message)
    end

    if (wizard.role.type == "Group::Root::Member") && birthday > Date.new(2009, 7, 30)
      message = I18n.t("groups.self_registration.create.flash.cmt_to_young")
      errors.add(:base, message)
    end
  end
end
