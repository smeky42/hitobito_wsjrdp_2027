# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A document key holds no "-" (Wsjrdp2027::DocumentFilename): the generated
# registration PDF is the key registration_generated, in its kind and in its
# documents. Renames only what still has the old key, so it does nothing
# where the rename was done already. The files keep their names.
class RenameRegistrationGeneratedDocumentKey < ActiveRecord::Migration[7.1]
  OLD_KEY = "registration-generated"
  NEW_KEY = "registration_generated"

  def up
    %w[wsjrdp_document_kinds wsjrdp_documents].each do |table|
      execute("UPDATE #{table} SET key = #{quote(NEW_KEY)} WHERE key = #{quote(OLD_KEY)}")
    end
  end

  # The old key is no valid key any more; nothing to restore.
  def down
  end

  private

  def quote(value) = connection.quote(value)
end
