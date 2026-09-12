# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# POST /wsjrdp/impersonate: the admin tab's person search (doc/roles.md ->
# "The finance cap"). The core's Person::ImpersonationController#create
# refuses out of a running impersonation; this one switches -- ends the
# current impersonation the way the core's #destroy does, then starts the
# next one the way its #create does -- and acts for the person who actually
# logged in: the origin user is the taker, and the origin user's ability is
# the one asked, since the impersonated person's rights are not the point.
#
# The bookkeeping is the core's, kept in step with it: the origin_user
# session key, the PaperTrail impersonate / impersonation_done events, the
# notification mail. Note that #current_user is memoized through
# #current_ability, so after a sign_in nothing here reads it again.
class Wsjrdp::ImpersonationController < ApplicationController
  # The check happens in #authorize_action, on the origin user's ability
  # while impersonating -- which CanCan's check_authorization cannot see.
  skip_authorization_check
  before_action :authorize_action

  def create
    person = Person.find(params[:person_id])
    return redirect_back(fallback_location: root_path) if person == actor || person == current_user

    end_impersonation if origin_user
    start_impersonation(person)
    redirect_to return_path
  end

  private

  # Back to the page the menu was opened on, so a switch does not send anybody
  # elsewhere -- a page the new person may not see answers with the usual
  # refusal. Only a path of our own is accepted, never an absolute or
  # protocol-relative URL.
  def return_path
    path = params[:return_to].to_s
    path.match?(%r{\A/(?![/\\])}) ? path : root_path
  end

  # The person who actually logged in.
  def actor
    @actor ||= origin_user || current_user
  end

  def end_impersonation
    previous_user = current_user
    sign_in(actor)
    PaperTrail::Version.create(main: previous_user, item: previous_user,
      whodunnit: actor, event: :impersonation_done)
    session[:origin_user] = nil
  end

  def start_impersonation(person)
    session[:origin_user] = actor.id
    sign_in(person)
    PaperTrail::Version.create(main: person, item: person, whodunnit: actor, event: :impersonate)

    if person.password? && person.email? && Settings.impersonate.notify
      Person::UserImpersonationMailer.completed(person, actor.full_name).deliver_later
    end
  end

  def authorize_action
    ability = origin_user ? Ability.new(actor) : current_ability
    ability.authorize!(:impersonate_user, Person)
  end
end
