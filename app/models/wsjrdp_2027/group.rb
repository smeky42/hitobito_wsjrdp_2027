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

    def support_cmt_mail_addresses_string
      support_cmt_mail_addresses&.join("\n")
    end

    def support_cmt_mail_addresses_string=(value)
      addresses = (value || "").tr("\n", ",").split(",").map { |s| s.strip.presence }.compact
      self.support_cmt_mail_addresses = addresses
    end

    def group_code_or_short_name
      group_code = (additional_info || {})["group_code"]
      group_code or short_name
    end
  end
end
