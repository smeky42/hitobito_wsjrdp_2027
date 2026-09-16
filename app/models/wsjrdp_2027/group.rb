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

  included do
    # Define additional used attributes
    # self.used_attributes += [:website, :bank_account, :description]
    # self.superior_attributes = [:bank_account]

    used_attributes.concat(WSJRDP_INTERNAL_ATTRS)
    paper_trail_options[:skip].concat(WSJRDP_INTERNAL_ATTRS.map(&:to_s))

    root_types Group::Root

    jsonb_accessor :additional_info, :unit_code, strip: true
    attribute :unit_code, :string

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
    # every unit and every IST group except the waiting lists. A waiting list
    # is told apart by its NAME ("UL Warteliste", "YP Warteliste", "IST
    # Warteliste") -- there is no flag for it -- while the registration groups
    # stay in.
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
