# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One row of the Reduktionen list (Fin::FeeReductionsController): a person with
# an active or a planned total fee reduction, and the person version that last
# changed the active reduction's amount -- when it took effect and who did it.
# Both are nil without such a version (a person with a plan only).
Fin::FeeReductionRow = Data.define(:person, :activated_at, :activated_by) do
  # The rows of the given people, each with its last amount change (one query
  # for the versions, one for their authors).
  def self.for(people)
    people = people.to_a
    versions = PaperTrail::Version
      .where(item_type: Person.sti_name, item_id: people.map(&:id), event: %w[create update])
      .where("object_changes ~ ?", "(?n)^wsjrdp_total_fee_reduction:")
      .order(:created_at, :id)
      .index_by(&:item_id)
    authors = Person.where(id: versions.values.filter_map(&:whodunnit)).index_by { |p| p.id.to_s }
    people.map do |person|
      version = versions[person.id] if person.active_total_fee_reduction != 0
      new(person: person, activated_at: version&.created_at, activated_by: authors[version&.whodunnit])
    end
  end

  # The planned reduction as the row's sub-row (Fin::FeeReductionPlan).
  def plans = planned? ? [Fin::FeeReductionPlan.new(row: self)] : []

  def id = person.id

  def planned? = person.planned_total_fee_reduction.present?

  # The regular fee as the fee computation takes it (Person#total_fee_cents).
  def regular_fee_cents = person.total_fee_cents + (person.active_total_fee_reduction * 100).to_i
end
