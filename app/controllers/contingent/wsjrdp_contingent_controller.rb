# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Kontingent > Übersicht: the comparison with the jamboree registration, the
# contingent roles against the contract, the people list (an expandable
# table with the Schnellauswahl), and the people whose jamboree role differs.
# The figures come from Wsjrdp2027::ContingentOverview; matrix cells, the
# list's default and the Schnellauswahl are filter trees of
# Wsjrdp2027::ContingentPeopleFilterSchema, so a number and its list agree.
class Contingent::WsjrdpContingentController < ApplicationController
  include Wsjrdp::TableStateful
  include WsjrdpContingentHelper

  PEOPLE_POLICY = wsjrdp_expandable_table_policy prefix: "co",
    columns: Wsjrdp2027::ContingentPeopleColumns::COLUMNS.codec,
    cols: {default: Wsjrdp2027::ContingentPeopleColumns::COLUMNS.default_keys},
    sort: {hidden: Wsjrdp2027::ContingentPeopleColumns::DEFAULT_ORDER},
    per_page: {default: 50},
    filter: {policy: :url, schema: Wsjrdp2027::ContingentPeopleFilterSchema,
             default: Wsjrdp2027::ContingentPeopleFilterSchema::DEFAULT,
             presets: Wsjrdp2027::ContingentPeopleFilterSchema::PRESETS}

  before_action :authorize_action

  helper_method :overview, :people_rows, :people_table_state, :people_filter_href

  # The people links of the IST page (wsjrdp_ist), switched by a cookie.
  def show_people_links
    cookies[:contingent_show_people_links] = true
    redirect_to contingent_ist_path
  end

  def hide_people_links
    cookies[:contingent_show_people_links] = false
    redirect_to contingent_ist_path
  end

  def index
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful).
  def apply
    wsjrdp_apply_table_filter(people_table_state, redirect_to: contingent_contingent_path)
  end

  private

  def authorize_action
    authorize!(:log, Group.root)
  end

  def overview = @overview ||= Wsjrdp2027::ContingentOverview.new

  def people_table_state = wsjrdp_expandable_table_state(PEOPLE_POLICY)

  def people_rows
    @people_rows ||= Wsjrdp::ExpandableTableRows.new(people_table_state,
      people_table_state.filter.scope(overview.entries),
      sort: Wsjrdp2027::ContingentPeopleColumns.sort_lambdas, tiebreaker: ->(entry) { entry.id })
  end

  # The page with the people list filtered by a tree (a matrix cell), at the
  # list.
  def people_filter_href(tree)
    contingent_contingent_path(people_table_state.param_name(:filter) => people_filter_wire(tree), :anchor => "co-list")
  end

  def people_filter_wire(tree) = people_table_state.filter.encode_tree(tree).to_s
end
