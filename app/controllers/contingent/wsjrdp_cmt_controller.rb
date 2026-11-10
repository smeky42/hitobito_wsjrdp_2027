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
    "KoLa",
    "Foodhouse",
    "BMT",
    "IT",
    "Finance",
    "Accounting",
    "Identity",
    "Logistics",
    "Unit-Support",
    "Media",
    "Wellbeing"
  ].freeze

  # The order of the jamboree roles on the page, the same in every section:
  # CMT, JPT, any other role ("andere Rolle"), EXT.
  ROLE_RANKS = {"CMT" => 0, "JPT" => 1, "EXT" => 3}.freeze
  OTHER_ROLE_RANK = 2

  TAG_NAMES = TEAM_NAMES.map { |s| (s == "HoC" || s == "eHoC") ? s : "#{s}-Team" }.freeze

  # Tags that make a team beyond the fixed list: any tag ending in this suffix.
  TEAM_TAG_SUFFIX = "-Team"

  # The teams in the order the page shows them: the fixed list first, then
  # every further "<Name>-Team" tag among the given tag names, alphabetically.
  # A new team thus shows up as soon as someone carries its tag; the fixed list
  # only sets the order of the known ones.
  def self.team_tag_names(tag_names)
    extra = tag_names.select { |name| name.end_with?(TEAM_TAG_SUFFIX) && name != TEAM_TAG_SUFFIX } - TAG_NAMES
    TAG_NAMES + extra.uniq.sort_by(&:downcase)
  end

  include ContractHelper

  before_action :authorize_action

  helper_method :cmt_teams

  def index
    @full_cmt_people = cmt_people.includes([:tags]).sort_by { |p| p.nickname_or_short_first_name.downcase }
    @cmt_people_by_tag = make_tag_to_people_hash(@full_cmt_people)
    @tag_names = self.class.team_tag_names(@cmt_people_by_tag.keys)
    @wsj_role_jpt_people = @full_cmt_people.select { |p| p.effective_wsj_role == "JPT" }
    @wsj_role_cmt_people = @full_cmt_people.select { |p| p.effective_wsj_role == "CMT" }
    @wsj_role_ext_people = @full_cmt_people.select { |p| p.effective_wsj_role == "EXT" }
    @wsj_role_other_people = @full_cmt_people.select { |p| !["JPT", "CMT", "EXT"].include?(p.effective_wsj_role) }
    # In blocks by jamboree role (ROLE_RANKS), by name within each block.
    @people_without_contract = @full_cmt_people.reject { |p| p.contract_status == "confirmed" }
      .each_with_index.sort_by { |p, i| [role_rank(p), i] }.map(&:first)
  end

  private

  def authorize_action
    authorize!(:log, Group.root)
  end

  # The root group's people, plus whoever holds an active role in it
  # from another primary group, e.g., external accountants.
  def cmt_people
    root_id = Group.root.id
    role_person_ids = Role.where(group_id: root_id).distinct.pluck(:person_id)
    Person.where(primary_group_id: root_id).or(Person.where(id: role_person_ids))
  end

  def role_rank(person) = ROLE_RANKS.fetch(person.effective_wsj_role, OTHER_ROLE_RANK)

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

  # One row per team, in the order of @tag_names, then a row for the
  # people counted in no team.
  def cmt_teams
    counted_in = {}
    rows = @tag_names.map do |tag_name|
      team_name = tag_name.delete_suffix(TEAM_TAG_SUFFIX)
      team_people = @cmt_people_by_tag[tag_name] || []
      # A guest needs only the "Guest-in-<Team>" tag, not the team's tag too.
      guests = @cmt_people_by_tag["Guest-in-#{team_name}"] || []
      next if team_people.empty? && guests.empty?

      leads = team_people.select { |p| p.has_tag?("Head-of-#{team_name}") }
      members = team_people - leads - guests
      counted_people = leads + members
      repeated = counted_people.select { |p| counted_in.key?(p.id) }
      new_people = counted_people - repeated
      row = {
        label: content_tag(:a, html_escape(team_name), href: tag_search_path(Group.root.id, tag_name)),
        size: counted_people.size,
        count: new_people.size,
        counted_in: repeated.to_h { |p| [p.id, counted_in[p.id]] },
        people_with_labels: [
          [(leads.size == 1) ? "Lead:" : "Leads:", leads],
          ["Mitglieder:", members],
          [(guests.size == 1) ? "Gast:" : "Gäste:", guests, {guest: true}]
        ]
      }
      new_people.each { |p| counted_in[p.id] = team_name }
      row
    end.compact
    without_team = @full_cmt_people.reject { |p| counted_in.key?(p.id) }
    if without_team.any?
      rows << {
        label: content_tag(:span, "—", class: "text-muted", title: "kein Team"),
        size: nil,
        count: without_team.size,
        people_with_labels: [[nil, without_team]]
      }
    end
    rows << {
      label: "Gesamt",
      count: counted_in.size + without_team.size,
      people_with_labels: []
    }
    rows
  end
end
