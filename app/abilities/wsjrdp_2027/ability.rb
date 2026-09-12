# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to ::Ability: accepts the finance cap and hands it to the
# UserContext the core builds inside its constructor (Wsjrdp2027::FinanceCap).
#
#   Ability.new(person)                                   # as before
#   Ability.new(person, max_finance_permission: :finance)  # capped
module Wsjrdp2027::Ability
  def initialize(user, max_finance_permission: nil)
    Wsjrdp2027::FinanceCap.with(max_finance_permission) { super(user) }
  end

  # The core keys caches on this; a capped ability must not share them with
  # the uncapped one of the same person.
  def identifier
    cap = user_context&.max_finance_permission
    cap ? "#{super}-fin-#{cap}" : super
  end
end
