# frozen_string_literal: true

module Wsjrdp2027::Group
  extend ActiveSupport::Concern

  included do
    # Define additional used attributes
    # self.used_attributes += [:website, :bank_account, :description]
    # self.superior_attributes = [:bank_account]

    root_types Group::Root

    store_accessor :additional_info, :unit_code
    store_accessor :additional_info, :support_cmt_mail_addresses

    def support_cmt_mail_addresses_string
      support_cmt_mail_addresses.join("\n")
    end

    def support_cmt_mail_addresses_string=(value)
      self.support_cmt_mail_addresses = value.tr("\n", ",").split(",").map { |s| s.strip }.compact
    end
  end
end
