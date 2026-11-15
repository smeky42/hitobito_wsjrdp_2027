# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The core's family links (family_members), extended by the wagon:
# - label: the link's own name for the relation, per direction -- each row
#   says what `other` is for `person` ("Aunt"), its inverse row what `person`
#   is for `other` ("Niece"). Empty: the kind's label.
# - additional_info: room for further data, as on the wagon's other tables.
class ExtendFamilyMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :family_members, :label, :string, null: true,
      comment: "Own name of the relation (what other is for person); empty: the kind's label"
    add_column :family_members, :additional_info, :jsonb, null: false, default: {}
  end
end
