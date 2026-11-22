# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The base of the Moss tabs Benutzer, Teams and Abteilungen: a filterable
# list, a record's page (also a row's detail) and an edit page for the few
# fields Hitobito owns. A subclass sets the model, POLICY and COLUMNS.
# Reading needs :show on the model, editing :update on the record.
class Fin::MossOrganisationController < Fin::FinController
  include WsjrdpFormHelper
  include Wsjrdp::TableStateful

  class_attribute :model_class, :row_id_prefix, :page_frame_prefix, :row_preloads
  # What the edit page may change; everything else comes from Moss.
  class_attribute :editable_attrs, default: [:comment].freeze

  before_action :authorize_action

  # The tab's list: filter and quick filter remembered.
  def self.list_policy(columns, schema)
    wsjrdp_expandable_table_policy prefix: "",
      columns: columns.codec,
      sort: {hidden: [["name", "asc"]]},
      cols: {default: columns.default_keys},
      per_page: {default: 50},
      filter: {policy: :remember, schema: schema, **schema::QUICK_FILTER},
      lifts: {policy: :remember},
      pane: {default: 0}
  end

  # A table of other Moss records on a record's detail, remembered per record.
  def self.nested_policy(prefix, columns, schema, hidden: [])
    wsjrdp_expandable_table_policy prefix: prefix,
      columns: columns.codec,
      sort: {hidden: [["name", "asc"]]},
      cols: {default: columns.default_keys - hidden},
      per_page: {default: 25},
      filter: {schema: schema, **schema::QUICK_FILTER},
      pane: {default: 0},
      store_key: -> { "#{controller_path}##{prefix}:#{params[:id]}" },
      level: {default: -> { table_state.level }}
  end

  helper_method :entry, :rows, :permitted_attrs, :cancel_url, :return_url,
    :detail_frame_on_page?, :detail_format_context, :page_frame_prefix, :row_id_prefix,
    :list_path, :entry_path, :edit_entry_path, :apply_path

  def index
    rows
  end

  # The record's page, or for a frame request its detail alone.
  def show
    authorize!(:show, entry)
    render(turbo_frame_request? ? :detail_frame : :show)
  end

  def edit
    authorize!(:update, entry)
  end

  def update
    authorize!(:update, entry)
    entry.attributes = permitted_params
    if entry.save
      redirect_after_save
    else
      render :edit, status: :bad_request
    end
  end

  # PRG target of the list's CNF filter builder.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: list_path)
  end

  def entry
    @entry ||= model_class.find(params[:id])
  end

  def table_state = wsjrdp_expandable_table_state(self.class::POLICY)

  # THE list: what the filter leaves, sorted and paged by the table's state.
  def rows
    @rows ||= filtered_rows(self.class::POLICY, self.class::COLUMNS, list_source, row_preloads || [])
  end

  # Is this the detail's frame on the record's own page?
  def detail_frame_on_page?
    turbo_frame_request_id == helpers.wsjrdp_detail_frame_id(page_frame_prefix, entry.id)
  end

  # WHERE the detail renders: the record's page, or a row's pane of the list.
  def detail_format_context
    if !turbo_frame_request? || detail_frame_on_page?
      Fin::AttrFormatContext.regular
    else
      Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: 1, lazy: true))
    end
  end

  def permitted_attrs = can?(:update, entry) ? editable_attrs : []

  def list_path(**query) = polymorphic_path(model_class, **query)

  def entry_path(record = entry, **query) = polymorphic_path(record, **query)

  def edit_entry_path(record = entry) = edit_polymorphic_path(record)

  def apply_path = polymorphic_path(model_class, action: :apply)

  private

  # The rows before the filter; a subclass adds its counts.
  def list_source = model_class.all

  # What a table's filter leaves of `source`, sorted and paged by its state.
  def filtered_rows(policy, columns, source, preload)
    state = wsjrdp_expandable_table_state(policy)
    Wsjrdp::ExpandableTableRows.new(state, state.filter.scope(source),
      sort: columns.sort_expressions, preload: preload, tiebreaker: "#{source.table_name}.id")
  end

  # PRG target of a nested table's filter; back to the record.
  def apply_nested(policy)
    authorize!(:show, entry)
    wsjrdp_apply_table_filter(wsjrdp_expandable_table_state(policy), redirect_to: entry_path)
  end

  def authorize_action
    authorize!(:show, model_class)
  end

  # Only the editable fields; a blank comment is "", a blank person none.
  def permitted_params
    attrs = params.require(model_class.model_name.param_key).permit(*editable_attrs)
    attrs[:comment] = attrs[:comment].to_s if attrs.key?(:comment)
    attrs[:person_id] = attrs[:person_id].presence if attrs.key?(:person_id)
    attrs
  end

  # Only a path on this site, so no other scheme ends up in a link.
  def return_url
    given = params[:return_url].to_s
    return entry_path if given.present? && !given.match?(%r{\A/(?![/\\])})

    return_url_or_fallback entry_path
  end

  # Back to the reading view: the record's page, the list with the row open,
  # or -- in a table on another page -- the row's detail.
  def redirect_after_save
    if !turbo_frame_request?
      redirect_to entry_path, status: :see_other
    elsif detail_frame_on_page?
      redirect_top entry_path
    elsif turbo_frame_request_id == helpers.wsjrdp_detail_frame_id(row_id_prefix, entry.id)
      redirect_top list_path(self.class::POLICY.param_name(:open) => entry.id)
    else
      redirect_to entry_path, status: :see_other
    end
  end

  def redirect_top(url)
    render turbo_stream: helpers.turbo_stream_action_tag(:redirect_top, url: url)
  end

  # In a frame the detail itself, else wherever the edit page was reached from.
  def cancel_url
    turbo_frame_request? ? entry_path : return_url
  end
end
