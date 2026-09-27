# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require HitobitoWsjrdp2027::Wagon.root.join("db/migrate/20260929100000_add_additional_info_to_service_tokens.rb")

# The migration adds the wagon's columns and fills the scopes of the existing
# rows from their core areas.
describe AddAdditionalInfoToServiceTokens do
  let(:migration) { described_class.new }
  let(:columns) { %w[additional_info acting_person_id scopes stage hmac_secret_key_fingerprint] }

  def existing = columns.select { |column| ActiveRecord::Base.connection.column_exists?(:service_tokens, column) }

  def quietly(&block) = ActiveRecord::Migration.suppress_messages(&block)

  it "goes down and up, filling the scopes from the core areas" do
    token = ServiceToken.create!(layer: groups(:root), name: "Alt", permission: "layer_read",
      people: true, invoices: true, mailing_lists: true)

    quietly { migration.migrate(:down) }
    ServiceToken.reset_column_information
    expect(existing).to eq([])

    quietly { migration.migrate(:up) }
    ServiceToken.reset_column_information
    expect(existing).to eq(columns)
    scopes = ActiveRecord::Base.connection.select_value("SELECT scopes FROM service_tokens WHERE id = #{token.id}")
    expect(ActiveRecord::Base.connection.select_values("SELECT unnest(scopes) FROM service_tokens WHERE id = #{token.id}"))
      .to eq(%w[people invoices mailing_lists]), scopes.inspect
  ensure
    ServiceToken.reset_column_information
  end
end
