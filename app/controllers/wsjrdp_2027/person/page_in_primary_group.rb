# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to the core's person pages history, log and security tools:
# without a group in the URL (/people/:id/history) the person's default group
# (Person#default_group, mostly the primary group) and the person by id
# alone, as the status page (Person::StatusController#group). With a group in
# the URL everything stays as the core has it.
module Wsjrdp2027::Person::PageInPrimaryGroup
  private

  def group
    return super if params[:group_id]

    @group ||= person_by_id.default_group
  end

  # The core's fetch_person sets @group on the way (the sheet draws it).
  def fetch_person
    return super if params[:group_id]

    group
    person_by_id
  end

  def person_by_id
    @person_by_id ||= ::Person.find(params[:id])
  end
end
