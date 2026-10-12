# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # The filter schema protocol (Wsjrdp::Filtering::FilterSchema) for an
  # array-backed dataset. The dataset module binds its SCHEMA to an
  # ArraySource instead of a relation and extends this module instead:
  #
  #   module DocumentManagement::RegistrationChainsFilterSchema
  #     extend Wsjrdp::Filtering::ArrayFilterSchema
  #     SOURCE = Wsjrdp::Filtering::ArraySource.define(:registration_chains) { |s| ... }
  #     SCHEMA = Wsjrdp::Filtering::Schema.define { |s| ... }
  #     def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)
  #   end
  #
  # Decoding, presets, chips and the builder work as for a relation;
  # Wsjrdp::TableState::Filter#scope then takes the Array of rows and answers
  # the rows the filter leaves (Wsjrdp::Filtering::ArrayCompiler).
  #
  # The strategy is the module's array_strategy: by default
  # Settings.filtering.array_strategy; a dataset may define its own
  # (`def self.array_strategy = :sql`).
  module ArrayFilterSchema
    include FilterSchema

    def compile(query, schema:, relation:)
      ArrayCompiler.apply(query, relation, schema: schema, strategy: array_strategy)
    end

    def array_strategy = ArrayCompiler.default_strategy
  end
end
