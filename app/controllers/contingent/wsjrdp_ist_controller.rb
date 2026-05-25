# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Contingent::WsjrdpIstController < ApplicationController
  include ContractHelper
  include WsjrdpContingentHelper

  PERSON_COLUMNS = [
    "id",
    "primary_group_id",
    "nickname",
    "first_name",
    "status",
    "payment_role",
    "wsj_role",
    "additional_info"
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
    # 45 - BMT
    @bmt_people = make_ist_grouped(
      Person.select(PERSON_COLUMNS).where(primary_group_id: [45]).includes(includes)
    )
    # 4 - IST Reg
    # 49 - IST Süd
    # 50 - IST Süd West
    # 51 - IST West
    # 52 - IST Nord Ost
    @ist_wo_bmt_people = make_ist_grouped(
      Person.select(PERSON_COLUMNS).where(primary_group_id: [4, 49, 50, 51, 52]).includes(includes)
    )
  end

  private

  def authorize_action
    authorize!(:log, Group.root)
  end

  def show_people_links?
    ActiveModel::Type::Boolean.new.cast(cookies[:contingent_show_people_links])
  end

  def make_ist_grouped(query)
    make_grouped(
      query,
      [->(p) { p.effective_wsj_role }, nil],
      [->(p) { p.primary_group.group_code_or_short_name_or_name || "???" }, nil],
      [->(p) { p.status || "???" }, nil]
    )
  end

  def make_grouped(people, *groupings)
    if groupings.size == 1
      group_by_proc, _ = groupings.first
      people.group_by(&group_by_proc).sort_by(&:first).map do |key, grouped_people|
        grouped_people.sort_by! { |p| p.nickname_or_short_first_name }
        [
          key,
          {people: grouped_people, size: grouped_people.size, num_rows: 1, groups: []}
        ]
      end
    else
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
end
