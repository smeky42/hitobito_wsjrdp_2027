# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::MossBookingsController < Fin::FinController
  include WsjrdpFormHelper
  include SubjectLinking

  prepend_before_action :map_id_to_moss_booking_id
  before_action :authorize_action

  helper_method :moss_booking
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :moss_booking_path
  helper_method :matching_accounting_entries

  def show
    @moss_booking ||= moss_booking
    render :show
  end

  def update
    @moss_booking ||= moss_booking
    authorize!(:update, moss_booking)
    moss_booking.attributes = permitted_params
    if moss_booking.save
      flash[:notice] = "Moss Buchung #{moss_booking.id} erfolgreich aktualisiert."
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  # "Erzeuge Buchung": the Beitragsbuchung for the person already linked.
  def create_accounting_entry
    authorize!(:update, moss_booking)
    subject = moss_booking.contribution_subject
    authorize!(:update, subject)
    authorize!(:create, AccountingEntry)
    create_accounting_entry_for(moss_booking, subject)
    respond_after_subject_link
  end

  # "Buchung für <Person> erzeugen": link the person AND create their
  # Beitragsbuchung, in one transaction. Refused (422, with the refreshed block)
  # once the booking has a person or a Beitragsbuchung
  # (MossBooking#open_for_new_entry?) or while the person already has a
  # matching Beitragsbuchung for this payment
  # (MossBooking#accounting_entries_matching_new_entry) -- the page may be
  # stale or the button clicked twice, and a second entry for one payment is
  # the mistake this button must not make. See doc/TODOs/TODO_moss_link_and_create_entry.md.
  def link_subject_and_create_accounting_entry
    authorize!(:update, moss_booking)
    person = linkable_person
    authorize!(:create, AccountingEntry)
    if !moss_booking.open_for_new_entry? ||
        moss_booking.accounting_entries_matching_new_entry(person).exists?
      return respond_after_subject_link(status: :unprocessable_entity)
    end

    MossBooking.transaction do
      assign_linked_subject(moss_booking, person)
      moss_booking.save!
      create_accounting_entry_for(moss_booking, person)
    end
    respond_after_subject_link
  end

  def link_accounting_entry
    authorize!(:update, moss_booking)
    tx = moss_booking
    subject = tx.contribution_subject
    authorize!(:update, subject)
    accounting_entry = AccountingEntry.find(params[:accounting_entry_id])
    accounting_entry.moss_booking_id = tx.id
    accounting_entry.moss_booking_link_meta = Fin::LinkMeta.manual(author_id: current_user.id)
    tx.accounting_entry_id = accounting_entry.id
    tx.save!
    accounting_entry.save!
    respond_after_subject_link
  end

  private

  def entry
    moss_booking
  end

  # The person link of a Moss booking carries its provenance
  # (contribution_subject_link_meta): who linked, when, by hand.
  def assign_linked_subject(booking, person)
    booking.subject = person
    booking.contribution_subject_link_meta = Fin::LinkMeta.manual(author_id: current_user.id)
  end

  # The Beitragsbuchung of `subject` for the booking `tx`, linked to it, with the
  # provenance of a hand-made link (who clicked, when).
  def create_accounting_entry_for(tx, subject)
    entry = AccountingEntry.create!(
      subject: subject,
      author: current_user,
      amount_cents: tx.amount_cents,
      amount_currency: tx.currency,
      description: tx.description,
      comment: tx.comment,
      value_date: tx.value_date,
      booking_date: tx.moss_transaction.booking_date,
      dbtr_name: tx.moss_transaction.fin_account&.owner_name,
      dbtr_address: tx.moss_transaction.fin_account&.owner_address,
      # cdtr_name:
      cdtr_iban: tx.moss_transaction.recipient_iban,
      cdtr_bic: tx.moss_transaction.recipient_bic,
      moss_booking_id: tx.id,
      moss_booking_link_meta: Fin::LinkMeta.manual(author_id: current_user.id)
    )
    tx.accounting_entry_id = entry.id
    tx.save!
  end

  # Every link action of this controller changes only the booking's person side.
  # A Turbo request gets back:
  #   * every occurrence of the booking's linking block on the page, re-rendered
  #     from a fresh record (fin/moss_bookings/_subject_links; replace_all, as
  #     the booking may show in more than one table), and
  #   * a `reload_frames` for every already loaded detail frame of its
  #     transaction (the Moss lists' lazy detail shows the persons too) -- see
  #     turbo_stream_actions.js.
  # Without Turbo the browser goes back to the wallet as before.
  def respond_after_subject_link(status: :ok)
    booking = MossBooking.find(moss_booking.id)
    respond_to do |format|
      format.turbo_stream do
        render status: status, turbo_stream: helpers.safe_join([
          turbo_stream.replace_all(helpers.moss_booking_subject_links_selector(booking),
            partial: "fin/moss_bookings/subject_links", locals: {booking: booking}),
          turbo_stream.action_all(:reload_frames,
            helpers.loaded_detail_frames_selector(booking.moss_transaction))
        ])
      end
      format.html do
        alert = "Keine Beitragsbuchung angelegt: die Buchung ist bereits verknüpft, oder es gibt schon eine passende." unless status == :ok
        redirect_to booking.moss_transaction.fin_account, alert: alert
      end
    end
  end

  def map_id_to_moss_booking_id
    params[:moss_booking_id] = params[:id] unless params.key?(:moss_booking_id)
  end

  def authorize_action
    authorize!(:show, moss_booking)
  end

  def moss_booking
    @moss_booking ||= MossBooking.find(params[:moss_booking_id])
  end

  def moss_booking_path(entry = nil)
    url_for(entry.nil? ? moss_booking : entry)
  end

  def return_url
    return_url_or_fallback url_for(moss_booking)
  end

  def cancel_url
    return_url
  end

  def matching_accounting_entries
    @matching_accounting_entries ||= moss_booking.accounting_entries_for_subject.select { |e|
      e.amount_cents == moss_booking.amount_cents
    }
  end

  def _transform_tx_params(params)
    if params[:contribution_subject].blank? || params[:contribution_subject_id].blank?
      params[:contribution_subject_id] = nil
      params[:contribution_subject_type] = nil
    elsif params[:contribution_subject_type].blank?
      params[:contribution_subject_type] = "Person"
    end
    params.except(:contribution_subject)
  end

  def model_params
    params.require(:moss_booking)
  end

  def permitted_attrs
    return [] unless can?(:update, moss_booking)

    [
      :comment,
      :contribution_subject, :contribution_subject_id, :contribution_subject_type,
      :accounting_entry, :accounting_entry_id
    ]
  end

  def permitted_params
    _transform_tx_params(model_params.permit(permitted_attrs))
  end
end
