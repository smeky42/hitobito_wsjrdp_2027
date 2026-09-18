# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What EVERY host of fin/bookings/_detail does the same way: one booking's
# detail is BOTH a page of its own and the pane an expandable table lazy-loads
# into an open row, and a mini-form inside it has to come back to whichever of
# the two asked.
#
# A host includes this and says only WHERE its bookings live
# (#booking_detail_path) -- the route differs per host (/fin/bookkeeping/bookings/:id,
# the group's own booking page), the behaviour does not.
module Fin::BookingDetailHost
  extend ActiveSupport::Concern

  # The extra key the EDIT PAGE submits next to the sub cost center select: the
  # NUMBER of a sub cost center to create for this booking's cost center. It is
  # no column of datev_bookings -- #resolve_new_sub_cost_center turns it into a
  # sub_cost_center_number before anything is written.
  NEW_SUB_COST_CENTER_FIELD = "new_sub_cost_center_number"
  NEW_SUB_COST_CENTER_PARAM = "datev_booking[#{NEW_SUB_COST_CENTER_FIELD}]"

  # What a booking WITHOUT a cost center is told when that field is filled in: a
  # sub cost center number is unique within its cost center only, so there is
  # nothing here for the new one to hang off.
  NO_COST_CENTER_ALERT = "Diese Buchung hat keine Kostenstelle – eine " \
                         "Unter-Kostenstelle kann dafür nicht angelegt werden."

  private

  # The path of ONE booking on THIS host. Every including controller defines it.
  def booking_detail_path(booking)
    raise NotImplementedError, "#{self.class} must define #booking_detail_path"
  end

  # The path of that booking's EDIT PAGE on THIS host.
  def booking_edit_path(booking)
    raise NotImplementedError, "#{self.class} must define #booking_edit_path"
  end

  # Resolves the sub cost center PAIR the edit page submits -- the select's
  # value and the number of a new sub cost center -- into the attributes to
  # write.
  #
  # A non-blank new number WINS over the select, which cannot offer a number
  # that does not exist yet. The row is found or created under the BOOKING'S OWN
  # cost center, since a sub cost center number is unique within its cost center
  # only, and it carries no name -- naming it is the Kostenstellen page's job.
  #
  # Returns the attributes with the extra key resolved away, or nil when the
  # booking has no cost center to create one under; the caller then answers with
  # NO_COST_CENTER_ALERT.
  def resolve_new_sub_cost_center(booking, attrs)
    attrs = attrs.to_h.stringify_keys
    number = attrs.delete(NEW_SUB_COST_CENTER_FIELD).to_s.strip
    return attrs if number.blank?
    return nil if booking.cost_center_number.blank?

    WsjrdpSubCostCenter.find_or_create_by!(cost_center_number: booking.cost_center_number,
      number: number)
    attrs.merge("sub_cost_center_number" => number)
  end

  # Is this request a Turbo frame asking for one row's detail?
  def turbo_frame_request? = request.headers["Turbo-Frame"].present?

  # The whole frame-vs-page half of a booking-detail #show: the format context
  # the detail renders in -- kept in @ctx, which the view hands the detail kit --
  # and, inside a frame, the answer without a layout (the frame's own markup is
  # all Turbo replaces).
  def show_booking_detail(state)
    @ctx = booking_detail_context(state)
    render layout: false if turbo_frame_request?
  end

  # An embedded pane knows the nesting depth of the table that asked for it, so
  # a detail inside a detail keeps counting; the record's own page is depth-less.
  def booking_detail_context(state)
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(
      Wsjrdp::TableContext.new(level: state.level, lazy: true)
    )
  end

  # Where a form of the detail view goes after its update. Three senders, three
  # answers:
  #
  # Inside a turbo frame the answer has to RE-RENDER THE FRAME that submitted --
  # #show does exactly that -- so a frame request goes to the booking's own path.
  # `redirect_back` would land on the HOST page (the Kostenstellen list, a
  # Sachkonto detail, ...), and that page carries no frame of this row: Turbo then
  # renders "Content missing", or, on the Buchungen list, replaces the row with
  # the still-unloaded "Wird geladen ..." placeholder.
  #
  # The EDIT PAGE names itself through its two submit buttons
  # (Fin::DetailHelper#fin_detail_edit_page_buttons): `stay` comes back here to
  # go on editing, `save` goes on to the reading page. `redirect_back` would
  # answer the edit page for both, since that is where the form stood.
  #
  # Everything else is a mini-form of the reading page (connect / unlink), which
  # runs with data-turbo=false; `redirect_back` is right for those -- it keeps
  # the user on the page they came from.
  #
  # The flash is only seen on the non-frame paths: a frame response renders
  # turbo-rails' minimal layout, which has no flash slot.
  def redirect_after_update(booking, **flash_args)
    if turbo_frame_request?
      redirect_to booking_detail_path(booking), **flash_args
    elsif params[:stay].present?
      redirect_to booking_edit_path(booking), **flash_args
    elsif params[:save].present?
      redirect_to booking_detail_path(booking), **flash_args
    else
      redirect_back fallback_location: booking_detail_path(booking), **flash_args
    end
  end
end
