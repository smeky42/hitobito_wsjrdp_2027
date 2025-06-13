# frozen_string_literal: true

require "iban-tools"

module Wsjrdp2027::Person
  # This is just local to this module, it doesn't override anything when this module in included
  GENDERS = %w[m w d].freeze

  def self.included(base)
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

      private

      def validate_iban_format
        return if sepa_iban.blank?

        normalized_iban = sepa_iban.gsub(/\s+/, "").upcase
        unless IBANTools::IBAN.valid?(normalized_iban)
          errors.add(:sepa_iban, I18n.t("people.finance_fields.invalid_iban"))
        end
      end
    end
  end
end
