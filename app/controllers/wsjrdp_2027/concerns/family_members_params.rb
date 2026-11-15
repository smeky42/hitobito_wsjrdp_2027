# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The family links a viewer may change in a person's form: only those to
# people the viewer may see. A unit leader edits the family of a person of
# their unit, but a link to a relative in another unit stays as it is -- not
# changed, not removed. The form shows such a row disabled
# (Wsjrdp2027::PeopleHelper#wsjrdp_family_link_editable?); here the rows are
# dropped from the params, so a crafted request changes nothing either. New
# links to someone the viewer may not see are dropped the same way.
module Wsjrdp2027::Concerns::FamilyMembersParams
  private

  def without_protected_family_members(person, attributes)
    return attributes if attributes.blank?

    other_ids = person.family_members.to_h { |link| [link.id.to_s, link.other_id] }
    attributes.reject do |_index, entry|
      other_id = entry[:id].present? ? other_ids[entry[:id].to_s] : entry[:other_id]
      other_id.present? && !family_member_visible?(other_id)
    end
  end

  def family_member_visible?(person_id)
    other = ::Person.find_by(id: person_id)
    other.present? && can?(:show, other)
  end
end
