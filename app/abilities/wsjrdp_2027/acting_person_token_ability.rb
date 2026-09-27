# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The ability of a service token with an acting person
  # (service_tokens.acting_person_id): an action is allowed when the token
  # allows it (TokenAbility: its kinds, its Zugriffsbereich, its layer) and
  # the acting person may do it (Ability, the wagon's rules included). The
  # token thus never does more than its person, and a person who loses a role
  # takes the token's rights with it at once.
  #
  # The acting person is the ability's user, so current_user names a real
  # person. PaperTrail still records the token as the author
  # (PaperTrailed#user_for_paper_trail asks for the service token first).
  class ActingPersonTokenAbility
    include CanCan::Ability

    attr_reader :token, :token_ability, :person_ability

    def initialize(token)
      @token = token
      @token_ability = ::TokenAbility.new(token)
      # Capped at the API key's highest finance permission: the lower of the
      # person's and the API key's tier applies.
      @person_ability = ::Ability.new(token.acting_person, max_finance_permission: token.finance_cap)
    end

    def user = token.acting_person

    def identifier = "#{token_ability.identifier}-person-#{user.id}"

    def can?(action, subject, *args)
      token_ability.can?(action, subject, *args) && person_ability.can?(action, subject, *args)
    end
  end
end
