# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddAdditionalInfoToServiceTokens < ActiveRecord::Migration[7.1]
  CORE_AREAS = %w[people groups events invoices event_participations mailing_lists].freeze

  def change
    add_reference :service_tokens, :acting_person, type: :integer, null: true,
      foreign_key: {to_table: :people, on_delete: :nullify}
    add_column :service_tokens, :scopes, :string, array: true, default: [], null: false
    add_column :service_tokens, :stage, :string, null: true
    add_column :service_tokens, :hmac_secret_key_fingerprint, :string

    add_column :service_tokens, :additional_info, :jsonb, default: {}, null: false

    reversible do |direction|
      direction.up do
        areas = CORE_AREAS.map { |area| "CASE WHEN #{area} THEN '#{area}' END" }.join(", ")
        execute "UPDATE service_tokens SET scopes = array_remove(ARRAY[#{areas}]::varchar[], NULL)"
      end
    end
  end
end
