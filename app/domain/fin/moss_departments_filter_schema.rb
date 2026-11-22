# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss departments dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md). Every condition is SQL on
# `moss_departments`.
module Fin::MossDepartmentsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :name, short_key: :q, label: "Name",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::MossOrganisationFilter::TEXT_OPERATORS,
      column: :name
    Fin::MossOrganisationFilter.common_attributes(s, "moss_departments")
  end

  # The Schnellauswahl, its condition fixed: shown, locked, never edited.
  QUICK_FILTER = {fixed_groups: [Fin::MossOrganisationFilter::IN_MOSS_GROUP]}.freeze

  def self.bound(except: nil)
    SCHEMA.bind(MossDepartment.all, except: except)
  end
end
