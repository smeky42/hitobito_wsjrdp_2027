# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the chains of the tab Anmelde-Dokumente
# (document_management/registration_documents/index).
module DocumentManagement::RegistrationDocumentsHelper
  # The widget's column Hashes, the full set (the columns menu picks from it).
  def registration_chain_table_columns(people_by_id)
    kind_labels = WsjrdpDocumentKind.where(subject_type: "Person", secondary_key: "").pluck(:key, :label).to_h
    cells = {
      "person" => ->(chain) { registration_chain_person(chain, people_by_id) },
      "person_id" => ->(chain) { chain.person_id },
      "key" => ->(chain) { registration_chain_kind(chain, kind_labels) },
      "files" => ->(chain) { chain.entries.size },
      "registered" => ->(chain) { chain.registered_count },
      "missing" => ->(chain) { registration_chain_missing(chain) },
      "state" => ->(chain) { t("document_management.registration_documents.states.#{chain.state}") }
    }
    DocumentManagement::RegistrationChainsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def registration_chain_person(chain, people_by_id)
    person = people_by_id[chain.person_id]
    return chain.person_name.presence || chain.person_id unless person

    link_to("#{person} (#{person.id})", person_path(person), data: {turbo_frame: "_top"})
  end

  # The label of the chain's document kind with its key as the tooltip; the
  # key alone when there is no kind.
  def registration_chain_kind(chain, kind_labels)
    label = kind_labels[chain.key]
    label ? content_tag(:span, label, title: chain.key) : content_tag(:span, chain.key, class: "font-monospace")
  end

  def registration_chain_missing(chain)
    count = chain.missing_count
    count.positive? ? content_tag(:span, count, class: "text-danger") : count
  end
end
