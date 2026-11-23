# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The reading page, the edit page and the save of ONE finance record whose
# detail is built on the detail kit (doc/fin/detail_partials.md): the reading
# page (show) is also what a table lazy-loads into a row, and there it carries
# the kit's inline edit. The host has the actions show, edit and update with
# their views; this concern answers where a save goes.
module Fin::DetailPages
  extend ActiveSupport::Concern
  include Fin::ReturnPath

  private

  # The record's own page, or a table row's detail (a turbo frame) at the
  # nesting level the table put into the frame's URL (§1 of the guide).
  def detail_format_context
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: params[:expandable_table_level], lazy: true))
  end

  # Saves the record with the given attributes. A save from a row's inline edit
  # shows the row's detail again, "Speichern und weiter" the edit page, a page
  # goes back where it came from. A failed save shows the same form again with
  # its errors: the row's (its form opens by itself) or the edit page.
  def save_detail(record, attributes, notice:)
    record.attributes = attributes
    return redirect_to(detail_after_save_path(record), notice: notice) if record.save

    flash.now[:alert] = validation_alert(record)
    @ctx = turbo_frame_request? ? detail_format_context : Fin::AttrFormatContext.regular
    render (turbo_frame_request? ? :show : :edit), status: :unprocessable_entity
  end

  def detail_after_save_path(record)
    page = url_for(action: :show, id: record.id, only_path: true)
    return page if turbo_frame_request?
    return url_for(action: :edit, id: record.id, return_url: return_path, only_path: true) if params[:stay].present?

    return_path || page
  end
end
