# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The payment role a debit was collected under ("EarlyPayer::Group::Unit::
# Member") in words: the contingent role (Wsjrdp2027::Person::
# SHORT_PAYMENT_ROLES) and the payer kind -- "YP · Ratenzahler". A role it
# does not know reads as it is.
module Fin::PaymentRoles
  PAYER_KINDS = {"EarlyPayer" => "Early Payer", "RegularPayer" => "Ratenzahler"}.freeze

  module_function

  def label(role)
    role = role.to_s
    short = Wsjrdp2027::Person::SHORT_PAYMENT_ROLES.find { |suffix, _| role.end_with?(suffix) }&.last
    payer = PAYER_KINDS[role.split("::").first]
    short ? [short, payer].compact.join(" · ") : role
  end
end
