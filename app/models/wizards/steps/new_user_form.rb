# frozen_string_literal: true

# Overwrite TODO is there something better?
class Wizards::Steps::NewUserForm < Wizards::Step
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :nickname, :string
  attribute :company_name, :string
  attribute :company, :boolean
  attribute :birthday, :date
  attribute :email, :string
  attribute :adult_consent, :boolean
  attribute :privacy_policy_accepted, :boolean

  validates :first_name, :last_name, :birthday, presence: true
  validates :adult_consent, acceptance: true, if: :requires_adult_consent?
  validates :company_name, presence: true, if: :company
  validate :assert_privacy_policy, if: :requires_policy_acceptance?
  validate :assert_role_policy
  validate :assert_age_policy

  delegate :requires_adult_consent?, :requires_policy_acceptance?, to: :wizard

  class_attribute :support_company, default: true

  def self.human_attribute_name(attr, options = {})
    super(attr, default: Person.human_attribute_name(attr, options))
  end

  def assignable_attributes
    attributes.compact_blank.symbolize_keys.except(:adult_consent)
  end

  private

  def assert_privacy_policy
    unless privacy_policy_accepted
      message = I18n.t("groups.self_registration.create.flash.privacy_policy_not_accepted")
      errors.add(:base, message)
    end
  end

  def assert_role_policy
    unless wizard.role.type.in?(['Group::Unit::Member', 'Group::Unit::UnapprovedLeader', 'Group::Ist::Member', 'Group::Root::Member'])
      message = I18n.t('groups.self_registration.create.flash.role_policy')
      errors.add(:base, message)
    end
  end

  def assert_age_policy
    if birthday.nil?
      message = I18n.t('groups.self_registration.create.flash.birthday_format')
      errors.add(:base, message)
      return
    end

    # Youth Particpants: born after 30 July 2009 but not later than 30 July 2013
    if birthday >= Date.new(2013, 7, 30)
      message = I18n.t('groups.self_registration.create.flash.to_young')
      errors.add(:base, message)
    end

    if (wizard.role.type == 'Group::Unit::Member') && birthday < Date.new(2009, 7, 30)
      message = I18n.t('groups.self_registration.create.flash.yp_to_old')
      errors.add(:base, message)
    end

    # Adults: born on or before 30 July 2009
    if (wizard.role.type == 'Group::Unit::UnapprovedLeader') && birthday > Date.new(2009, 7, 30)
      message = I18n.t('groups.self_registration.create.flash.ul_to_young')
      errors.add(:base, message)
    end

    if (wizard.role.type == 'Group::Ist::Member') && birthday > Date.new(2009, 7, 30)
      message = I18n.t('groups.self_registration.create.flash.ist_to_young')
      errors.add(:base, message)
    end

    if (wizard.role.type == 'Group::Root::Member') && birthday > Date.new(2009, 7, 30)
      message = I18n.t('groups.self_registration.create.flash.cmt_to_young')
      errors.add(:base, message)
    end
  end
end
