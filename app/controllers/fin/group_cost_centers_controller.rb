# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Gruppen-Kostenstellen", the second tab of the Verwaltung area
# (/fin/admin/group_cost_centers). THE editor of
# groups.additional_info["cost_center_numbers"] -- the cost centers a group's
# Buchhaltung tab shows.
#
# The assignment is explicit throughout: nothing is derived from a group's name
# or code, and nothing is pre-filled. The page is ONE form over every group of
# Group.finance_configurable, saved in one request; the numbers are written
# through Group#update!.
class Fin::GroupCostCentersController < Fin::FinController
  before_action :authorize_action

  helper_method :groups, :cost_centers, :cost_center_options, :numbers_of,
    :shared_numbers_of, :unassigned_cost_center_count

  def index
  end

  # One request carries the lists of every group. Nothing is saved before all
  # of them check out, and only the groups whose list actually differs are
  # written -- so an untouched row records no version.
  def update
    lists = submitted_lists
    return redirect_with_alert(t("fin.group_cost_centers.unknown_group")) if lists.nil?

    unknown = lists.values.flatten.uniq - cost_centers_by_number.keys
    if unknown.any?
      # Nothing is saved: a typo in one number leaves the whole page untouched.
      return redirect_with_alert(t("fin.group_cost_centers.unknown_numbers",
        numbers: unknown.sort.join(", ")))
    end

    changed = lists.reject { |group, numbers| numbers.sort == numbers_of(group).sort }
    # An empty list removes the key (delete_on_blank).
    changed.each { |group, numbers| group.update!(cost_center_numbers: numbers) }
    redirect_to fin_admin_group_cost_centers_path, notice: saved_notice(changed.size)
  end

  private

  def authorize_action
    authorize!(:configure_finance, Group)
  end

  def saved_notice(count)
    return t("fin.group_cost_centers.unchanged") if count.zero?

    t("fin.group_cost_centers.saved", count: count)
  end

  def redirect_with_alert(message)
    redirect_to fin_admin_group_cost_centers_path, alert: message
  end

  # The submitted lists as {group => numbers}, or nil as soon as one key names
  # a group the area does not configure. Every select posts a hidden "" of its
  # own, so a cleared one still arrives -- dropping the blanks is what turns it
  # into the empty list.
  def submitted_lists
    raw = params[:cost_center_numbers]
    submitted = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : {}
    by_id = groups.index_by { |group| group.id.to_s }
    return nil if submitted.keys.any? { |group_id| by_id[group_id.to_s].nil? }

    submitted.to_h do |group_id, numbers|
      [by_id[group_id.to_s], clean_numbers(numbers)]
    end
  end

  def clean_numbers(numbers)
    Array(numbers).map { |number| number.to_s.strip }.compact_blank.uniq
  end

  def groups
    @groups ||= Group.finance_configurable.to_a
  end

  def numbers_of(group) = Array(group.cost_center_numbers)

  # Every cost center of the master data, by number -- the options of every
  # select and the lookup behind every number.
  def cost_centers
    @cost_centers ||= WsjrdpCostCenter.order(:number).to_a
  end

  # The options of every select: the bare number as the value, the number and
  # the short name as the label.
  def cost_center_options
    @cost_center_options ||= cost_centers.map do |cost_center|
      ["#{cost_center.number} — #{cost_center.display_short_name}", cost_center.number]
    end
  end

  def cost_centers_by_number
    @cost_centers_by_number ||= cost_centers.index_by(&:number)
  end

  # number -> the groups carrying it. A number in more than one group is marked
  # on the row; nothing forbids it, it is only worth seeing.
  def groups_by_cost_center_number
    @groups_by_cost_center_number ||= groups.each_with_object(Hash.new { |h, k| h[k] = [] }) do |group, index|
      numbers_of(group).each { |number| index[number] << group }
    end
  end

  # The group's stored numbers another group claims as well, as
  # [number, other groups] -- rendered from the STORED state, next to the row.
  def shared_numbers_of(group)
    numbers_of(group).filter_map do |number|
      others = groups_by_cost_center_number[number].reject { |other| other == group }
      [number, others] if others.any?
    end
  end

  # How many cost centers of the master data no group claims.
  def unassigned_cost_center_count
    @unassigned_cost_center_count ||=
      (cost_centers_by_number.keys - groups_by_cost_center_number.keys).size
  end
end
