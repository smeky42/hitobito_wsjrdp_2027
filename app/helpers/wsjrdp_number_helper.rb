# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpNumberHelper
  include ActionView::Helpers::NumberHelper

  extend ActiveSupport::Concern

  included do
    def cents_to_eur_or_nil(cents)
      if cents.nil?
        nil
      else
        cents.to_f / 100.0
      end
    end

    def cents_to_eur_display_or_nil(cents, separator: ",", delimiter: ".", format: "%n")
      if cents.nil?
        nil
      else
        eur = cents.to_f / 100.0
        number_to_currency(eur, separator: separator, delimiter: delimiter, format: format)
      end
    end

    def eur_to_cents_or_nil(eur)
      if eur.blank?
        nil
      else
        (eur.to_f * 100.0).round
      end
    end
  end

  module ClassMethods
    # rubocop:disable Style/RedundantInterpolation
    def eur_attribute(name, cents_attr:)
      define_method(:"#{name}") do
        cents = send(cents_attr)
        cents_to_eur_or_nil(cents)
      end
      define_method(:"#{name}=") do |value|
        cents = eur_to_cents_or_nil(value)
        send(:"#{cents_attr}=", cents)
      end
      attribute name.to_sym, :float
      define_method(:"#{name}_display") do
        cents = send(cents_attr)
        cents_to_eur_display_or_nil(cents)
      end
      define_method(:"#{name}_input_field_options") do
        cents = send(cents_attr)
        value = cents_to_eur_display_or_nil(cents, delimiter: "")
        {value: value, type: "number", lang: "de-DE", step: 0.01, autocomplete: "off"}
      end
    end
    # rubocop:enable Style/RedundantInterpolation
  end
end
