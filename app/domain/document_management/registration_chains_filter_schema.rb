# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The chains of the tab Anmelde-Dokumente
# (DocumentManagement::RegistrationDocumentsController) for the generic CNF
# filter: an array-backed dataset (doc/wsjrdp/generic_filter_builder.md,
# "Filtering arrays"), filtered in Ruby.
#
# The quick filters (PRESETS): the state as an exclusive group, and the chains
# with a missing file.
module DocumentManagement::RegistrationChainsFilterSchema
  extend Wsjrdp::Filtering::ArrayFilterSchema

  STATES = %w[new partial complete].freeze

  SOURCE = Wsjrdp::Filtering::ArraySource.define(:registration_chains) do |s|
    s.field :person_id, :integer
    s.field :person_name, :text
    s.field :key, :text
    s.field :files, :integer, ->(chain) { chain.entries.size }
    s.field :registered, :integer, ->(chain) { chain.registered_count }
    s.field :missing, :integer, ->(chain) { chain.missing_count }
    s.field :state, :text, ->(chain) { chain.state.to_s }
  end

  KEY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Wsjrdp2027::RegistrationDocuments::KEYS.map { |key| [key, key] }
  })

  STATE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    STATES.map { |state| [state, I18n.t("document_management.registration_documents.states.#{state}")] }
  })

  COUNT_OPERATORS = %i[nonzero between gte lte eq].freeze

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :person_name, short_key: :q, label: "Person",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: :person_name
    s.attribute key: :person_id, short_key: :pid, label: "Person (ID)",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[eq between],
      column: :person_id
    s.attribute key: :key, short_key: :k, label: "Art",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :key, options: KEY_OPTIONS
    s.attribute key: :state, short_key: :st, label: "Stand",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :state, options: STATE_OPTIONS
    s.attribute key: :files, short_key: :f, label: "Dateien",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: COUNT_OPERATORS, column: :files
    s.attribute key: :registered, short_key: :r, label: "registriert",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: COUNT_OPERATORS, column: :registered
    s.attribute key: :missing, short_key: :m, label: "fehlen",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: COUNT_OPERATORS, column: :missing
  end

  # The members' labels are document_management.registration_documents.states.*
  # -- written out, because the constant is built when the class loads.
  PRESETS = [
    {group: "state", attribute: "state", operator: "in", exclusive: true,
     members: [{key: "new", label: "nicht registriert", value: "new"},
       {key: "partial", label: "unvollständig", value: "partial"},
       {key: "complete", label: "vollständig", value: "complete"}]},
    {key: "missing", label: "mit fehlender Datei", slots: [[["missing", "nonzero"]]]}
  ].freeze

  def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)

  def self.array_strategy = :ruby
end
