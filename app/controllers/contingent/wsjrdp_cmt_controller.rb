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

  def index
    @tag_names = TAG_NAMES
    @full_cmt_people = Person.where(primary_group_id: 1).sort_by { |p| p.nickname_or_short_first_name.downcase }
    @cmt_people_by_tag = make_tag_to_people_hash(@full_cmt_people)
    @wsj_role_jpt_people = @full_cmt_people.select { |p| p.wsj_role == "JPT" }
    @wsj_role_cmt_people = @full_cmt_people.select { |p| p.wsj_role == "CMT" }
    @wsj_role_other_people = @full_cmt_people.select { |p| !["JPT", "CMT"].include?(p.wsj_role) }
  end

  private

  def authorize_action
    authorize!(:log, Person)
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
end
