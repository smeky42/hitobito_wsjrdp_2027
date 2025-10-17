# frozen_string_literal: true

require "iban-tools"
require "geocoder"

module Wsjrdp2027::Person
  include ContractHelper

  # This is just local to this module, it doesn't override anything when this module in included
  GENDERS = %w[m w d].freeze
  BUDDY_ID_FORMAT = /^(?<tag>[a-zA-Z0-9_äöüÄÖÜß]+-[a-zA-Z0-9_äöüÄÖÜß]+)-(?<id>\d+)$/

  def self.included(base)
    rdp_attrs = [:status, :early_payer, :rdp_association, :rdp_association_region, :rdp_association_sub_region, :rdp_association_group]
    Person::PUBLIC_ATTRS += rdp_attrs
    Person::FILTER_ATTRS += rdp_attrs
    Person.used_attributes += rdp_attrs

    base.extend Geocoder::Model::Base

    # This hack is needed to make Person::GENDERS return the right value
    base.send(:remove_const, :GENDERS) if base.const_defined?(:GENDERS)
    base.const_set(:GENDERS, GENDERS)

    base.class_eval do
      # We need to remove the existing validator with just two genders first
      _validators[:gender].reject! { |v| v.is_a? ActiveModel::Validations::InclusionValidator }
      # ...and the callback for the validator
      cb = _validate_callbacks.find { |c| c.filter.is_a? ActiveModel::Validations::InclusionValidator and c.filter.attributes.include? :gender }
      _validate_callbacks.delete(cb)

      # Then add the attr with validator and the setter again
      i18n_enum :gender, GENDERS
      i18n_setter :gender, (GENDERS + [nil])

      validate :validate_iban_format
      validate :validate_buddy_id_ul
      validate :validate_buddy_id_yp

      before_save :geocode_full_address, if: :address_changed?

      def unit_code_display
        make_unit_code_display(unit_code)
      end

      def cluster_code_display
        make_unit_code_display(cluster_code)
      end

      private

      def validate_iban_format
        return if sepa_iban.blank?

        normalized_iban = sepa_iban.gsub(/\s+/, "").upcase
        unless IBANTools::IBAN.valid?(normalized_iban)
          errors.add(:sepa_iban, I18n.t("people.finance_fields.invalid_iban"))
        end
      end

      def validate_buddy_id(field)
        buddy_id = send(field)
        return nil if buddy_id.blank?

        id_parts = buddy_id.match(BUDDY_ID_FORMAT)
        if id_parts.nil?
          errors.add(field, :invalid)
          return nil
        end

        buddy = Person.find_by(id: id_parts[:id])
        if buddy.nil? ||
            buddy.buddy_id != id_parts[:tag]
          errors.add(field, :invalid)
          return nil
        end

        if buddy == self
          errors.add(field, :buddy_self)
          return nil
        end

        buddy
      end

      def validate_buddy_id_ul
        buddy = validate_buddy_id(:buddy_id_ul)
        return if buddy.nil?

        unless ul?(buddy)
          errors.add(:buddy_id_ul, :buddy_no_ul)
        end
      end

      def validate_buddy_id_yp
        buddy = validate_buddy_id(:buddy_id_yp)
        return if buddy.nil?

        unless yp?(buddy)
          errors.add(:buddy_id_yp, :buddy_no_yp)
        end
      end

      def geocode_full_address
        results = Geocoder.search(full_address)

        if results.first
          self.latitude = results.first.latitude
          self.longitude = results.first.longitude
        end
      end

      def full_address
        [street, housenumber, zip_code, town, country].compact.join(", ")
      end

      def address_changed?
        street_changed? || housenumber_changed? || zip_code_changed? || town_changed? || country_changed?
      end
    end
  end
end
