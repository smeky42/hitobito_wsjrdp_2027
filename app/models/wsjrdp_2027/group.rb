# frozen_string_literal: true

module Wsjrdp2027::Group
  extend ActiveSupport::Concern

  DELETE_IF_BLANK_ATTRS = [:support_cmt_mail_addresses, :unit_code].freeze

  included do
    # Define additional used attributes
    # self.used_attributes += [:website, :bank_account, :description]
    # self.superior_attributes = [:bank_account]

    root_types Group::Root

    store_accessor :additional_info, :unit_code
    store_accessor :additional_info, :support_cmt_mail_addresses

    before_save :normalize_additional_info_attrs

    def support_cmt_mail_addresses_string
      support_cmt_mail_addresses&.join("\n")
    end

    def support_cmt_mail_addresses_string=(value)
      addresses = (value || "").tr("\n", ",").split(",").map { |s| s.strip.presence }.compact
      if addresses.blank?
        additional_info.delete("support_cmt_mail_addresses")
      else
        self.support_cmt_mail_addresses = addresses
      end
    end

    private

    def normalize_additional_info_attrs
      [:unit_code].each do |attr|
        val = send(attr)
        send(:"#{attr}=", val.strip) if val.respond_to?(:strip)
      end
      DELETE_IF_BLANK_ATTRS.each do |attr|
        additional_info.delete(attr.to_s) if send(attr).blank?
      end
    end
  end
end
