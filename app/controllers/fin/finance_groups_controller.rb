# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Gruppen-Finanzzugriff", the first tab of the Verwaltung area
# (/fin/admin/finance_groups). THE editor of
# people.additional_info["finance_group_ids"] -- the per-group finance access
# of the CMT leaders and the like (doc/roles.md -> "Finance on a group's
# page").
#
# A TWO-STAGE editor: the page collects every add, level change and removal
# locally and hands the whole round over as one JSON change list (#apply).
# Nothing is written unless every change of the list passes, and each person is
# written once, through Person#update!, so the version is recorded as the model
# builds it.
class Fin::FinanceGroupsController < Fin::FinController
  before_action :authorize_action

  # The two access levels the page offers. Anything else in the store (an
  # "update" without a "show", say) is shown as raw text and can only be
  # replaced or removed here.
  LEVELS = ["show", "show,update"].freeze

  # A unit whose name is a family letter and a number ("A1") belongs to that
  # letter's family; every other unit falls into "Sonstige Units".
  UNIT_FAMILY_NAME = /\A([A-Z])\d+\z/

  # One (person, group) row. `group` is nil for an id that resolves to no
  # group; `tokens` are the stored tokens of that entry.
  Entry = Struct.new(:person, :group_id, :group, :tokens, keyword_init: true)

  # One change of the list: the level the (person, group) entry is to carry,
  # nil meaning the entry is to go.
  Change = Struct.new(:person_id, :group_id, :level, keyword_init: true)

  helper_method :entries, :candidates, :configurable_groups, :levels,
    :filter_group_id, :filter_person_id, :filter_people,
    :families, :filter_family, :family_filter_params

  def index
  end

  # The one write of the page: the whole change list of one editing round.
  def apply
    @changes = parsed_changes
    return redirect_rejected(t("fin.finance_groups.rejected_format")) if @changes.nil?

    reason = rejection_reason
    return redirect_rejected(reason) if reason

    redirect_to fin_admin_finance_groups_path, notice: applied_notice(write_changes)
  end

  private

  def authorize_action
    authorize!(:configure_finance, Group)
  end

  def redirect_rejected(reason)
    redirect_to fin_admin_finance_groups_path, alert: reason
  end

  # params[:changes] is a JSON array of {person_id, group_id, level}, level
  # being one of LEVELS or null for a removal. Anything else -- broken JSON, a
  # value that is no array, an element that is no object -- answers nil, and
  # the request is rejected before a single change is looked at.
  def parsed_changes
    raw = JSON.parse(params[:changes].to_s)
    return nil unless raw.is_a?(Array) && raw.all?(Hash)

    raw.map do |item|
      Change.new(person_id: item["person_id"].to_s, group_id: item["group_id"].to_s,
        level: item["level"]&.to_s)
    end
  rescue JSON::ParserError
    nil
  end

  # EVERY change is checked before anything is written, so one bad change
  # leaves the whole list unsaved. The message of the first rejection, or nil.
  def rejection_reason
    @changes.filter_map { |change| change_rejection(change) }.first
  end

  # A removal only needs the person to exist -- the group may be anything, so a
  # stale entry can be cleared out. Giving a level is the stricter case: the
  # group has to be one the area configures and the person one the field works
  # for. None of it is taken on trust, because all of it arrives as a request
  # parameter.
  def change_rejection(change)
    return t("fin.finance_groups.rejected_person") if people_of_changes[change.person_id].nil?
    return nil if change.level.nil?

    unless LEVELS.include?(change.level)
      return t("fin.finance_groups.rejected_level")
    end
    unless configurable_group_ids.include?(change.group_id)
      return t("fin.finance_groups.rejected_group")
    end
    unless candidate_ids.include?(change.person_id)
      return t("fin.finance_groups.rejected_person")
    end

    nil
  end

  # Per person: merge the levels into the stored hash, drop the removals and
  # write once -- only where the hash really differs, so an unchanged person
  # gets no version. The counts are taken against the STORED state, which is
  # why a change to the level that is already there counts nothing.
  def write_changes
    counts = {added: 0, changed: 0, removed: 0}
    @changes.group_by(&:person_id).each do |person_id, list|
      person = people_of_changes[person_id]
      before = stored(person)
      after = before.dup
      list.each do |change|
        count_change(counts, before, change)
        change.level.nil? ? after.delete(change.group_id) : after[change.group_id] = change.level
      end
      # An empty hash removes the key altogether (delete_on_blank).
      person.update!(finance_group_ids: after) if after != before
    end
    counts
  end

  def count_change(counts, before, change)
    if change.level.nil?
      counts[:removed] += 1 if before.key?(change.group_id)
    elsif !before.key?(change.group_id)
      counts[:added] += 1
    elsif before[change.group_id] != change.level
      counts[:changed] += 1
    end
  end

  def applied_notice(counts)
    return t("fin.finance_groups.unchanged") if counts.values.sum.zero?

    t("fin.finance_groups.applied", **counts)
  end

  # The people the change list names, by id as a string. A person id that
  # resolves to nobody is simply missing here, and the change is rejected.
  def people_of_changes
    @people_of_changes ||= Person.where(id: @changes.map(&:person_id))
      .index_by { |person| person.id.to_s }
  end

  def configurable_group_ids
    @configurable_group_ids ||= configurable_groups.map { |group| group.id.to_s }
  end

  def candidate_ids
    @candidate_ids ||= candidates.map { |person| person.id.to_s }
  end

  # The stored hash as a plain Hash we may build a new value from.
  def stored(person) = (person.finance_group_ids || {}).to_h

  # Every (person, group) entry there is, ordered by person then group name.
  # The filters narrow the ROWS, not the store.
  def entries
    @entries ||= begin
      rows = people_with_entries.flat_map { |person| entries_of(person) }
      rows = rows.select { |row| group_family(row.group) == filter_family } if filter_family
      rows = rows.select { |row| row.group_id == filter_group_id } if filter_group_id
      rows = rows.select { |row| row.person.id.to_s == filter_person_id } if filter_person_id
      rows.sort_by { |row| [row.person.last_name.to_s, row.person.first_name.to_s, row.person.id, group_label(row)] }
    end
  end

  def entries_of(person)
    stored(person).map do |group_id, value|
      Entry.new(person: person, group_id: group_id.to_s, group: groups_by_id[group_id.to_s],
        tokens: Person.finance_group_tokens(value))
    end
  end

  # jsonb key existence. Spelled with -> IS NOT NULL and not with the ?
  # operator, because ActiveRecord reads a ? in a condition string as a bind
  # placeholder.
  def people_with_entries
    @people_with_entries ||= Person
      .where("people.additional_info -> 'finance_group_ids' IS NOT NULL")
      .order(:last_name, :first_name, :id)
      .to_a
  end

  # The groups the entries point at -- including ones the area no longer
  # configures, so such a row is still listed (and removable).
  def groups_by_id
    @groups_by_id ||= begin
      ids = people_with_entries.flat_map { |person| stored(person).keys }.uniq
      Group.where(id: ids).index_by { |group| group.id.to_s }
    end
  end

  def group_label(row) = row.group&.name.to_s

  def configurable_groups
    @configurable_groups ||= Group.finance_configurable.to_a
  end

  def candidates
    @candidates ||= Person.finance_group_candidates.to_a
  end

  # The people the person filter offers: everybody who has an entry.
  def filter_people = people_with_entries

  def levels = LEVELS

  def filter_group_id = params[:group_id].presence

  def filter_person_id = params[:person_id].presence

  def filter_family = params[:family].presence

  # The families the filter offers, as [label, param] pairs, derived from the
  # configurable groups alone: "Alle", one entry per unit family there is, the
  # remaining units and the IST groups. nil is the param of "Alle".
  def families
    @families ||= begin
      letters = configurable_groups.filter_map { |group| unit_family_letter(group) }.uniq.sort
      entries = [[t("fin.finance_groups.families.all"), nil]]
      letters.each do |letter|
        entries << [t("fin.finance_groups.families.unit", letter: letter), "unit:#{letter}"]
      end
      entries << [t("fin.finance_groups.families.other_units"), "unit:other"] if family_exists?("unit:other")
      entries << [t("fin.finance_groups.families.ist"), "ist"] if family_exists?("ist")
      entries
    end
  end

  def family_exists?(family)
    configurable_groups.any? { |group| group_family(group) == family }
  end

  # The family of a group: "unit:A" for a unit named "A1", "unit:other" for
  # every other unit (the registration groups among them), "ist" for an IST
  # group. nil for an id that resolves to no group.
  def group_family(group)
    return nil if group.nil?
    return "ist" if group.is_a?(::Group::Ist)

    letter = unit_family_letter(group)
    letter ? "unit:#{letter}" : "unit:other"
  end

  def unit_family_letter(group)
    group.name.to_s[UNIT_FAMILY_NAME, 1] if group.is_a?(::Group::Unit)
  end

  # The query the family links carry: the family plus the other two filters, so
  # switching the family keeps them.
  def family_filter_params(family)
    {group_id: filter_group_id, person_id: filter_person_id, family: family}.compact_blank
  end
end
