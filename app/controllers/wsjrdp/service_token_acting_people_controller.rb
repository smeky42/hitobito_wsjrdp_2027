# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# GET /wsjrdp/service_tokens/acting_people: the person search behind the
# acting person field of a service token (Wsjrdp2027::StandardFormBuilder),
# for admins only.
#
# The people search the wagon gives Person::QueryController returns only
# people the searcher may edit, from three characters on. An acting person may
# be anybody, a person without roles such as person 1 included, so this search
# returns every person whose name, company, nickname, town or zero-padded id
# matches. A number, leading zeros allowed, also finds the person with that
# id. The core's autocomplete asks from three characters on, so person 1 is
# found as "001" or "0001".
class Wsjrdp::ServiceTokenActingPeopleController < Person::QueryController
  ID_TERM = /\A0*(\d+)\z/

  def index
    render json: found_people.map(&:as_typeahead)
  end

  private

  def found_people
    term = search_param
    id = term[ID_TERM, 1]
    by_id = id ? scope.where(id: id.to_i).to_a : []
    by_search = (term.size >= 3) ? list_entries.limit(limit).to_a : []
    (by_id + by_search).uniq.first(limit).map { |person| PersonDecorator.new(person) }
  end

  def authorize_action
    authorize!(:query, Person)
    raise CanCan::AccessDenied unless ::ServiceToken.acting_person_admin?(current_person)
  end
end
