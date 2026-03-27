# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Contingent::WsjrdpContingentController < ApplicationController
  include ContractHelper
  include WsjrdpContingentHelper

  TEAM_NAMES = [
    "HoC",
    "eHoC",
    "CMT-Management",
    "IST",
    "IT",
    "Finance",
    "Identity",
    "Logistics",
    "Unit-Support",
    "Media",
    "Wellbeing"
  ].freeze

  TAG_NAMES = TEAM_NAMES.map { |s| (s == "HoC" || s == "eHoC") ? s : "#{s}-Team" }.freeze

  PERSON_COLUMNS = [
    "id",
    "primary_group_id",
    "nickname",
    "first_name",
    "status",
    "wsj_role"
  ].freeze

  before_action :authorize_action

  helper_method :show_people_links?

  def show_people_links
    cookies[:contingent_show_people_links] = true
    Rails.logger.debug { "cookies[:contingent_show_people_links]: #{cookies[:contingent_show_people_links].inspect}" }
    redirect_to contingent_contingent_path
  end

  def hide_people_links
    cookies[:contingent_show_people_links] = false
    Rails.logger.debug { "cookies[:contingent_show_people_links]: #{cookies[:contingent_show_people_links].inspect}" }
    redirect_to contingent_contingent_path
  end

  def index
    Rails.logger.debug { "cookies[:contingent_show_people_links]: #{cookies[:contingent_show_people_links].inspect}" }
    includes = [:primary_group]
    includes << :tags if show_people_links?
    query = Person.select(PERSON_COLUMNS).where(primary_group_id: [1, 4, 45]).includes(includes)
    @cmt_ist_people = make_grouped(
      query,
      [->(p) { p.wsj_role }, nil],
      [->(p) { p.primary_group.group_code_or_short_name_or_name }, nil],
      [->(p) { p.status }, nil]
    )
  end

  private

  def authorize_action
    authorize!(:log, Person)
  end

  def show_people_links?
    ActiveModel::Type::Boolean.new.cast(cookies[:contingent_show_people_links])
  end

  def make_grouped(people, *groupings)
    if groupings.size == 1
      group_by_proc, _ = groupings.first
      return people.group_by(&group_by_proc).sort_by(&:first).map do |key, grouped_people|
        grouped_people.sort_by! { |p| p.nickname_or_short_first_name }
        [
          key,
          {people: grouped_people, size: people.size, num_rows: 1, groups: []}
        ]
      end
    end

    first_grouping, *groupings = groupings
    group_by_op, _ = first_grouping
    people.group_by(&group_by_op).sort_by(&:first).map do |key, grouped_people|
      subgroups = make_grouped(grouped_people, *groupings)
      num_rows = subgroups.map { |_, h| h[:num_rows] }.sum
      [
        key,
        {people: grouped_people, size: grouped_people.size, num_rows: num_rows, groups: subgroups}
      ]
    end
  end
end
