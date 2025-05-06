# frozen_string_literal: true

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
    end
  end

end