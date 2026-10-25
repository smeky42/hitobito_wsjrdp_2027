# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What the SEPA mandate (Export::Pdf::Registration::Sepa) needs of a person.
  module SepaMandateRequirements
    ATTRS = %i[first_name last_name birthday town sepa_name sepa_address sepa_iban].freeze

    module_function

    # The missing ones, as attribute names; :payment_plan without
    # installments.
    def missing(person)
      missing = ATTRS.select { |attr| person.public_send(attr).blank? }
      missing << :payment_plan unless installments?(person)
      missing
    end

    def installments?(person)
      person.yme_list.present?
    rescue NoMethodError
      false
    end
  end
end
