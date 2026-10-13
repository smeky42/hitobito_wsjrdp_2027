# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Einstellungen > Ländercodes: what Wsjrdp::CountryLookup makes of each entry
# of the people's nationalities (Person#passport_nationality), and the one-off
# switch of those lists to ISO codes. Admins only.
class CountryCodesController < ApplicationController
  # The Administrator, as whom the scripts write (wsjrdp2027._pg).
  SCRIPT_WHODUNNIT = "1"

  before_action { authorize!(:country_codes, Person) }

  # The roles the table can be narrowed to (wsjrdp_role).
  ROLES = %w[CMT UL YP IST BMT EXT].freeze
  # The answers of "Visum benötigt" (visa_needed) that need a visa.
  VISA_NEEDED = %w[yes_have_one yes_need_support].freeze
  # A contract in force (Wsjrdp2027::Person::CONTRACT_STATUSES).
  CONTRACT_IN_FORCE = %w[confirmed replacement_pending].freeze

  # One table of the entries, narrowed by params: people (all, or with a
  # contract in force), nationalities (the first of each person, or all) and
  # roles (several; all without the param). The test run shows the same
  # people.
  def index
    @people_mode = (params[:people] == "contract") ? "contract" : "all"
    @nationality_mode = (params[:nationality] == "main") ? "main" : "all"
    @roles = params.key?(:roles) ? Array(params[:roles]).compact_blank & ROLES : ROLES
    @view_params = {people: @people_mode, nationality: @nationality_mode, roles: [""] + @roles}
    @visa_people = visa_people
    @entries = entries
    @test_run = test_run_rows if params[:test_run].present?
  end

  # Each known entry becomes its code, an unknown one stays; saved through the
  # model, so the person log shows the change. A person whose value would not
  # change is not saved. The log names the Administrator (person 1), as for a
  # run of the scripts in wsjrdp_scripts, with one mutation for the run.
  def migrate
    count = 0
    PaperTrail.request(whodunnit: SCRIPT_WHODUNNIT,
      controller_info: {whodunnit_type: "Person", mutation_id: "country-codes-#{request.request_id}"}) do
      Person.where.not(passport_nationality: [nil, ""]).find_each do |person|
        codes = Wsjrdp::CountryLookup.codes_of(person.passport_nationality)
        next if codes == person.passport_nationality

        person.passport_nationality = codes
        person.save!(validate: false)
        count += 1
      end
    end
    redirect_to country_codes_path, notice: t(".done", count: count)
  end

  private

  # [entry, people, {role => people}, code or nil, people who need a visa]
  # for each entry of the nationalities of the chosen people, most frequent
  # first; the people without a nationality in a row of their own (entry
  # nil), last. The people who need a visa do not follow the view: all of
  # them, by their main nationality (visa_people), an entry of theirs listed
  # even where no chosen person has it.
  def entries
    chosen = chosen_people(with_nationality: false)
      .flat_map do |person|
        list = Wsjrdp::CountryLookup.split(person.passport_nationality)
        list = list.first(1) if @nationality_mode == "main"
        list.empty? ? [[nil, person]] : list.map { |entry| [entry, person] }
      end
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    (chosen.keys | @visa_people.keys)
      .map do |entry|
        people = chosen.fetch(entry, [])
        [entry, people.size, people.map(&:wsjrdp_role).tally,
          entry && Wsjrdp::CountryLookup.find_country_by_any_name(entry), @visa_people.fetch(entry, [])]
      end
      .sort_by { |entry, count, _roles, _code, visa| [entry.nil? ? 1 : 0, -count, -visa.size, entry.to_s] }
  end

  # Everyone who needs a visa (VISA_NEEDED), whatever the view: main
  # nationality (nil for none) => people, by id.
  def visa_people
    Person.where("jamboree_data->>'visa_needed' IN (?)", VISA_NEEDED).order(:id)
      .group_by { |person| Wsjrdp::CountryLookup.split(person.passport_nationality).first }
  end

  # The people the view asks for, by id; only those with a nationality
  # unless with_nationality: false.
  def chosen_people(with_nationality: true)
    people = Person.includes(:primary_group, :roles).order(:id)
    people = people.where.not(passport_nationality: [nil, ""]) if with_nationality
    people = people.where(contract_status: CONTRACT_IN_FORCE) if @people_mode == "contract"
    people.select { |person| @roles.include?(person.wsjrdp_role) }
  end

  # The rows a test run can leave out (TEST_RUN_HIDE): no change, "Deutsch" to
  # "DE", "DE" staying "DE".
  TEST_RUN_HIDE = {
    "unchanged" => ->(old, new) { old == new },
    "deutsch_de" => ->(old, new) { old == "Deutsch" && new == "DE" },
    "de_de" => ->(old, new) { old == "DE" && new == "DE" }
  }.freeze

  # What the switch would store for each of the chosen people, nothing saved:
  # [person, old value, new value], without the rows hidden by params[:hide].
  def test_run_rows
    hide = TEST_RUN_HIDE.values_at(*Array(params[:hide]).map(&:to_s)).compact
    rows = chosen_people
      .map { |person| [person, person.passport_nationality, Wsjrdp::CountryLookup.codes_of(person.passport_nationality)] }
    @test_run_total = rows.size
    @test_run_changed = rows.count { |_person, old, new| old != new }
    rows.reject { |_person, old, new| hide.any? { |rule| rule.call(old, new) } }
  end
end
