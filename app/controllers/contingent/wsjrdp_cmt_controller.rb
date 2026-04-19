# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Contingent::WsjrdpCmtController < ApplicationController
  include WsjrdpContingentHelper

  TEAM_NAMES = [
    "HoC",
    "eHoC",
    "CMT-Management",
    "IST",
    "BMT",
    "IT",
    "Finance",
    "Identity",
    "Logistics",
    "Unit-Support",
    "Media",
    "Wellbeing"
  ].freeze

  TAG_NAMES = TEAM_NAMES.map { |s| (s == "HoC" || s == "eHoC") ? s : "#{s}-Team" }.freeze

  include ContractHelper

  before_action :authorize_action

  helper_method :cmt_teams

  def index
    @tag_names = TAG_NAMES
    @full_cmt_people = Person.where(primary_group_id: 1).includes([:tags]).sort_by { |p| p.nickname_or_short_first_name.downcase }
    @cmt_people_by_tag = make_tag_to_people_hash(@full_cmt_people)
    @wsj_role_jpt_people = @full_cmt_people.select { |p| p.effective_wsj_role == "JPT" }
    @wsj_role_cmt_people = @full_cmt_people.select { |p| p.effective_wsj_role == "CMT" }
    @wsj_role_other_people = @full_cmt_people.select { |p| !["JPT", "CMT"].include?(p.effective_wsj_role) }
  end

  private

  def authorize_action
    authorize!(:log, Group.root)
  end

  def make_tag_to_people_hash(people)
    h = {}
    people.each do |p|
      p.tags.each do |tag|
        h[tag.name] = [] if h[tag.name].nil?
        h[tag.name] << p
      end
    end
    h
  end

  def cmt_teams
    sum_people = 0
    overall_used_ids = Set.new
    rows = TAG_NAMES.map do |tag_name|
      team_people = @cmt_people_by_tag[tag_name] || []
      if team_people.size > 0
        team_name = tag_name.delete_suffix("-Team")
        leads = team_people.select { |p| p.has_tag?("Head-of-#{team_name}") }
        guests = team_people.select { |p| p.has_tag?("Guest-in-#{team_name}") }
        guests_ids = Set.new(guests.map(&:id))
        leads_ids = Set.new(leads.map(&:id))
        used_ids = guests_ids | leads_ids
        new_leads = leads.select { |p| !overall_used_ids.include?(p.id) }
        members = team_people.select { |p| !used_ids.include?(p.id) }
        overall_used_ids.merge(leads_ids)
        overall_used_ids.merge(members.map(&:id))
        label = content_tag(:a, html_escape(team_name), href: tag_search_path(1, tag_name))
        team_count = new_leads.size + members.size
        sum_people += team_count
        {
          label: label,
          count: team_count,
          people_with_labels: [
            [(leads.size == 1) ? "Lead:" : "Leads:", leads],
            ["Mitglieder:", members],
            [(guests.size == 1) ? "Gast:" : "Gäste:", guests]
          ]
        }
      end
    end.compact
    rows << {
      label: "Gesamt",
      count: sum_people,
      people_with_labels: []
    }
    rows
  end
end
