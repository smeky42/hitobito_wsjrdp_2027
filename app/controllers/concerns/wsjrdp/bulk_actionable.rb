# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Runs the bulk action a table's bar posts (Wsjrdp::BulkActions,
# doc/wsjrdp/expandable_table.md, "Bulk actions"):
#
#   def bulk
#     redirect_to list_path(state.wire_params), **run_bulk_action(ACTIONS, scope: filtered_rows,
#       atoms: ->(scope, keys) { scope.where(atom: keys) })
#   end
#
# The bar posts `bulk_action` (the action's key), the action's param, and the
# selection: the checked ids (`id_param`), or `all_param` -- "1" for every row
# of `scope`, else a comma-separated list of the quick-select's atoms, which
# `atoms` turns into the rows of `scope` that carry them. Ids outside `scope`
# never reach the action. The action's `authorize` is checked with authorize!
# (a refused action raises CanCan::AccessDenied); its `apply` runs inside a
# transaction. Answers the flash for the redirect: the action's done message,
# or an alert -- nothing selected, an unknown action, or the ArgumentError
# the action raised for a value it refuses (nothing written then).
#
# The bar's menus show which rows an action will touch: when a panel opens,
# the bar posts the same selection with the action and its value to the
# table's preview endpoint, which answers with #render_bulk_preview -- the rows
# the selection resolves to, the same way as for the action (with the action's
# `partition`, the rows it changes and the ones it leaves alone), at most
# BULK_PREVIEW_LIMIT of them:
#
#   def bulk_preview
#     render_bulk_preview(ACTIONS, scope: filtered_rows, atoms: ...,
#       columns: ->(view) { view.my_table_columns.select { |col| PREVIEW_KEYS.include?(col[:key]) } })
#   end
module Wsjrdp::BulkActionable
  extend ActiveSupport::Concern

  BULK_PREVIEW_LIMIT = 200

  private

  # Renders the rows the posted selection resolves to
  # (shared/wsjrdp/_expandable_table_bulk_preview), without layout: the
  # count, at most `limit` rows in `order` with the cells of `columns`
  # (->(view) { column Hashes with :key, :label, :cell }), and how many more.
  def render_bulk_preview(actions, scope:, columns:, atoms: nil, id_param: :ids, all_param: :select_all,
    order: {id: :desc}, preload: nil, limit: BULK_PREVIEW_LIMIT)
    ids = bulk_selected_ids(scope, atoms, id_param, all_param)
    selected = scope.klass.where(id: ids)
    action = actions[params[:bulk_action]]
    part = bulk_partition(action, selected)
    affected = part ? part.affected : selected
    load = ->(relation) { (preload ? relation.preload(preload) : relation).reorder(order).limit(limit).to_a }
    groups = Array(part&.groups).filter_map do |group|
      count = group.rows.count(:all)
      next if count.zero?

      {text: group.text.gsub("%{count}", count.to_s), warning: group.warning, count: count,
       rows: group.warning ? load.call(group.rows) : []}
    end
    render partial: "shared/wsjrdp/expandable_table_bulk_preview", layout: false,
      locals: {rows: load.call(affected), count: affected.count(:all), noun: actions.noun, columns: columns,
               extra_columns: Array(part&.columns), groups: groups}
  rescue ArgumentError => e
    render plain: e.message, status: :unprocessable_entity
  end

  def run_bulk_action(actions, scope:, atoms: nil, id_param: :ids, all_param: :select_all)
    action = actions[params[:bulk_action]]
    return {alert: "Unbekannte Aktion."} unless action

    authorize!(*action.authorize) if action.authorize
    ids = bulk_selected_ids(scope, atoms, id_param, all_param)
    return {alert: "Keine #{actions.noun[:many]} ausgewählt."} if ids.empty?

    value = action.param && params[action.param.name].to_s
    if (part = bulk_partition(action, scope.klass.where(id: ids)))
      ids = part.affected.pluck(:id)
      return {alert: "Keine der ausgewählten #{actions.noun[:many]} ist betroffen."} if ids.empty?
    end
    count = ActiveRecord::Base.transaction { send(action.apply, ids, value) }
    {notice: action.done_message(count, target: value && action.target_in(self, value))}
  rescue ArgumentError => e
    {alert: e.message}
  end

  # The action's Partition of the selected rows, nil without `partition:`.
  def bulk_partition(action, selected)
    return nil unless action&.partition

    send(action.partition, selected, action.param && params[action.param.name].to_s)
  end

  def bulk_selected_ids(scope, atoms, id_param, all_param)
    spec = params[all_param].to_s
    return scope.pluck(:id) if spec == "1"
    if spec.present?
      raise ArgumentError, "Diese Tabelle hat keine Schnellauswahl." unless atoms

      return atoms.call(scope, spec.split(",")).pluck(:id)
    end

    scope.where(id: Array(params[id_param]).map(&:to_i)).pluck(:id)
  end
end
