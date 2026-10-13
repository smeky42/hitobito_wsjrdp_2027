# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Until now the page "Daten für den Veranstalter" labelled the travel document
# type official_passport "Personalausweis", so every stored official_passport
# is a national identity card. It becomes national_identity_card, with the text
# the export sends as the organizer's other travel document
# (Wsjrdp2027::Person::JamboreeData::NATIONAL_IDENTITY_CARD_TEXT).
class OfficialPassportToNationalIdentityCard < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE people
         SET jamboree_data = jamboree_data
               || '{"travel_document_type": "national_identity_card", "travel_document_other": "National identity card"}'::jsonb
       WHERE jamboree_data->>'travel_document_type' = 'official_passport'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE people
         SET jamboree_data = (jamboree_data - 'travel_document_other')
               || '{"travel_document_type": "official_passport"}'::jsonb
       WHERE jamboree_data->>'travel_document_type' = 'national_identity_card'
    SQL
  end
end
