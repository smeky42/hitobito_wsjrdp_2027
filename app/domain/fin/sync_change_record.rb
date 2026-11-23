# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One change of a sync run, as the record of a fin_detail
# (fin/sync_runs/_change_detail): its fields are the columns it changes; the
# values and labels come from
# Fin::SyncHelper#fin_format_fields_of_fin_sync_change_record.
#
#   change   a Wsjrdp::Sync::Plan::Change
#   notices  the notices about its record
#   fields   notice code => the column its chip sits at (ListPart.notice_fields)
#   people   person id => Person, for the links (fin_sync_people)
#   model    the model it writes (MossTeam, Person, ...), for the labels; nil
#            leaves the column names
class Fin::SyncChangeRecord
  attr_reader :change, :people

  def self.human_attribute_name(attr, _options = {}) = attr.to_s

  def initialize(change, notices, fields, people, model: nil)
    @change = change
    @notices = notices || []
    @fields = fields
    @people = people
    @model = model
  end

  def label(column) = @model ? @model.human_attribute_name(column) : column

  def create? = change.action == "create"

  def columns = change.values.keys

  # The notices of one column; nil gives those at none of its columns.
  def notices(column) = notices_by_column[column] || []

  private

  def notices_by_column
    @notices_by_column ||= @notices.group_by { |notice| @fields[notice.code].presence_in(columns) }
  end
end
