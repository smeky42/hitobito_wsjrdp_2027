# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::Group
  extend ActiveSupport::Concern

  include WsjrdpJsonbHelper

  WSJRDP_INTERNAL_ATTRS = [
    :additional_info
  ].freeze

  # The size of a unit as planned at the Unit-Einteilung, the size it is to
  # have, the number of its unit leaders and of its patrols, where a unit has
  # not stored its own (additional_info "initial_unit_size" /
  # "expected_unit_size" / "expected_ul_number" / "expected_patrol_number").
  DEFAULT_INITIAL_UNIT_SIZE = 40
  DEFAULT_EXPECTED_UNIT_SIZE = 40
  DEFAULT_EXPECTED_UL_NUMBER = 4
  DEFAULT_EXPECTED_PATROL_NUMBER = 4
  # The day of the Unit-Einteilung, where a unit has not stored its own
  # (additional_info "unit_formed_date"): who joined a unit on it or before
  # was there from the start, only who came later moved up (nachgerückt).
  DEFAULT_UNIT_FORMED_DATE = Date.new(2026, 1, 7)

  # A waiting list ("UL Warteliste", "YP Warteliste", "IST Warteliste", ...)
  # is told apart by its NAME -- there is no flag for it.
  WAITING_LIST_NAME = /warteliste/i

  class_methods do
    def waiting_list_name?(name) = WAITING_LIST_NAME.match?(name.to_s)
  end

  def waiting_list? = self.class.waiting_list_name?(name)

  included do
    # Define additional used attributes
    # self.used_attributes += [:website, :bank_account, :description]
    # self.superior_attributes = [:bank_account]

    used_attributes.concat(WSJRDP_INTERNAL_ATTRS)
    paper_trail_options[:skip].concat(WSJRDP_INTERNAL_ATTRS.map(&:to_s))

    root_types Group::Root

    jsonb_accessor :additional_info, :unit_code, strip: true
    attribute :unit_code, :string

    # additional_info["initial_unit_size"] / ["expected_unit_size"] /
    # ["expected_ul_number"] / ["expected_patrol_number"]: a unit's size at
    # the Unit-Einteilung, the size it is to have, how many unit leaders and
    # how many patrols it is to have, where they differ from the rule
    # (DEFAULT_INITIAL_UNIT_SIZE, DEFAULT_EXPECTED_UNIT_SIZE,
    # DEFAULT_EXPECTED_UL_NUMBER, DEFAULT_EXPECTED_PATROL_NUMBER); blank
    # removes the key, and the rule applies again (#effective_initial_unit_size,
    # #effective_expected_unit_size, #effective_expected_ul_number,
    # #effective_expected_patrol_number).
    jsonb_accessor :additional_info, :initial_unit_size
    attribute :initial_unit_size, :integer
    jsonb_accessor :additional_info, :expected_unit_size
    attribute :expected_unit_size, :integer
    jsonb_accessor :additional_info, :expected_ul_number
    attribute :expected_ul_number, :integer
    jsonb_accessor :additional_info, :expected_patrol_number
    attribute :expected_patrol_number, :integer
    validates :initial_unit_size, :expected_unit_size, :expected_ul_number, :expected_patrol_number,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true

    # The store keeps what a form sends, a String; a whole number goes in as
    # an Integer, anything else stays as given -- so the validation above
    # refuses it instead of the value getting lost.
    %i[initial_unit_size expected_unit_size expected_ul_number expected_patrol_number].each do |attr|
      define_method(:"#{attr}=") do |value|
        text = value.to_s.strip
        super(text.match?(/\A-?\d+\z/) ? text.to_i : text)
      end
    end

    def effective_initial_unit_size = initial_unit_size || DEFAULT_INITIAL_UNIT_SIZE

    def effective_expected_unit_size = expected_unit_size || DEFAULT_EXPECTED_UNIT_SIZE

    def effective_expected_ul_number = expected_ul_number || DEFAULT_EXPECTED_UL_NUMBER

    def effective_expected_patrol_number = expected_patrol_number || DEFAULT_EXPECTED_PATROL_NUMBER

    # additional_info["unit_formed_date"]: the day the unit was formed, as an
    # ISO date; blank removes it, and DEFAULT_UNIT_FORMED_DATE applies again.
    jsonb_accessor :additional_info, :unit_formed_date, cast: :date

    def unit_formed_date = ActiveModel::Type::Date.new.cast(super)

    def effective_unit_formed_date = unit_formed_date || DEFAULT_UNIT_FORMED_DATE

    jsonb_accessor :additional_info, :support_cmt_mail_addresses
    attribute :support_cmt_mail_addresses, :string, array: true

    # additional_info["cost_center_numbers"]: the cost centers of this group,
    # as an array of cost-center NUMBERS. Numbers are alphanumeric strings
    # ("A1", "A1-R"), never just digits. The list is what the group's
    # Buchhaltung tab shows; it is edited on /fin/admin/group_cost_centers and
    # nowhere else -- nothing derives it from the group's name or code. An
    # empty list removes the key (delete_on_blank).
    jsonb_accessor :additional_info, :cost_center_numbers
    attribute :cost_center_numbers, :string, array: true

    # The cost-center records the numbers name, by number. A number without a
    # master record simply has no row here.
    def cost_centers
      WsjrdpCostCenter.where(number: Array(cost_center_numbers)).order(:number)
    end

    # The groups the Verwaltung area lets a finance configuration be made for:
    # every unit and every IST group except the waiting lists
    # (WAITING_LIST_NAME, here as SQL) -- the registration groups stay in.
    scope :finance_configurable, -> {
      where(type: [::Group::Unit.sti_name, ::Group::Ist.sti_name], deleted_at: nil)
        .where.not(arel_table[:name].matches("%Warteliste%"))
        .order(:type, :name)
    }

    def support_cmt_mail_addresses_string
      support_cmt_mail_addresses&.join("\n")
    end

    def support_cmt_mail_addresses_string=(value)
      addresses = (value || "").tr("\n", ",").split(",").map { |s| s.strip.presence }.compact
      self.support_cmt_mail_addresses = addresses
    end

    def group_code_or_short_name
      group_code = (additional_info || {})["group_code"]
      group_code.presence || short_name.presence
    end

    def group_code_or_short_name_or_name
      group_code_or_short_name || name.presence
    end
  end
end
