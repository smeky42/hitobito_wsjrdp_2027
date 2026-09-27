# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The "Abmeldung" sub-tab of a person's Finanzen section
# (/people/:id/deregistration). The page reads what is written down about a
# deregistration, section by section; the Abmeldung erfassen section is edited
# where it stands, through the turbo frame its body lives in.
#
# PersonInPrimaryGroup supplies the group its sheet and left navigation need --
# and maps :id to :person_id, which keeps the resource reachable under both
# spellings. That callback is registered before :authorize_action, so #person
# already finds its key when the authorization runs.
class Person::DeregistrationController < ApplicationController
  include PersonInPrimaryGroup
  include ContractHelper
  include WsjrdpFormHelper

  before_action :authorize_action

  helper_method :return_url
  helper_method :permitted_attrs

  # What the flash's change lines are made of: U+2192 between the two values,
  # an en dash where there is no value. Wsjrdp2027::DeregistrationRecord holds
  # the words, so the person log reads like the flash.
  CHANGE_ARROW = Wsjrdp2027::DeregistrationRecord::CHANGE_ARROW
  BLANK_VALUE = Wsjrdp2027::DeregistrationRecord::BLANK_VALUE
  DATE_ATTRS = %i[deregistration_effective_date deregistration_requested_date].freeze
  CENTS_ATTRS = %i[deregistration_actual_compensation_cents].freeze
  # The two flags whose absent value means "shown", which is what a checked box
  # is stored as (#normalise_flags).
  BOOLEAN_ATTRS = %i[
    deregistration_form_show_contractual_compensation
    deregistration_refund_receipt_show_default_explanation
  ].freeze

  # The collapsibles of the page, in the order they stand: the four sections,
  # each with the preview of its document where it has one. Which of them are
  # open is kept in the session under SESSION_KEY, as a list of keys; nothing
  # kept means the first one alone.
  SECTIONS = %w[capture form form_preview creditor receipt receipt_preview].freeze
  DEFAULT_OPEN_SECTIONS = %w[capture].freeze
  SESSION_KEY = :deregistration_open_sections

  # What a save says that wrote nothing the page shows -- a form that sent the
  # defaults again, or one that shed a stored default.
  NO_CHANGE_NOTICE = "Angaben zur Abmeldung wurden nicht verändert"

  def show
    @person ||= person
    @group ||= group
    # The page previews what the receipt will say, so it builds the same
    # object the PDF is made of -- and above it, what the creditor the refund
    # is paid to looks like in Moss.
    @refund_creditor = Wsjrdp2027::RefundCreditor.new(person)
    @refund_receipt = Wsjrdp2027::RefundReceipt.new(person, generated_by: current_user)
    @deregistration_form = Wsjrdp2027::DeregistrationForm.new(person)
    @dereg_open_sections = remembered_sections
    render :show
  end

  # The form of the Abmeldung erfassen section. The page asks for it as a frame
  # and takes the frame out of the answer; a deep link gets the same frame as a
  # whole page, so both ways lead to the same form.
  def edit
    @person ||= person
    @group ||= group
    render :edit
  end

  # The declaration the person signs to withdraw from the contract: built from
  # the person on every request, nothing is stored. What the page does not know
  # the document leaves as a line to fill in by hand. The page offers it only
  # where DeregistrationForm#available? says so; a URL typed in by hand is sent
  # back to the page with the same reason -- its picture included.
  def form
    @person ||= person
    @group ||= group
    form = Wsjrdp2027::DeregistrationForm.new(person)
    unless form.available?
      flash[:alert] = helpers.deregistration_form_unavailable_text(form)
      return redirect_to person_deregistration_path(person)
    end

    # The form is made by #create_form and not before; until then there is no
    # document to show.
    unless form.created?
      flash[:alert] = t("people.deregistration_form.not_created")
      return redirect_to person_deregistration_path(person)
    end

    send_document(form)
  end

  # Makes the form: stores its day, which every later PDF reuses, and comes
  # back to the page with the form's section open.
  def create_form
    form = Wsjrdp2027::DeregistrationForm.new(person)
    if form.available?
      form.record_creation!
      session[SESSION_KEY] = SECTIONS & (remembered_sections | ["form"])
      flash[:notice] = t("people.deregistration_form.created")
    else
      flash[:alert] = helpers.deregistration_form_unavailable_text(form)
    end
    redirect_to person_deregistration_path(person)
  end

  # Throws the made form away: its day goes, and the next PDF is made -- and
  # dated -- afresh.
  # The receipt goes with it, since it is made from the same captured data,
  # and so do the captured data and the deadline the form fixed. An entered
  # deadline stays.
  def discard_form
    person.deregistration_form_created_date = nil
    person.deregistration_effective_reply_due_date = nil
    clear_receipt
    Wsjrdp2027::DeregistrationSnapshot.for(person).clear!
    person.save! if person.changed?
    flash[:notice] = t("people.deregistration_form.discarded")
    redirect_to person_deregistration_path(person)
  end

  # The slip the finance team pays the refund from: built from the person on
  # every request and never stored, so it says what the page says. What it
  # carries is edited on the form, which is why this one only reads.
  def refund_receipt
    receipt = Wsjrdp2027::RefundReceipt.new(person, generated_by: current_user)
    # Made by #create_receipt and not before; until then there is nothing to
    # show.
    unless receipt.created?
      flash[:alert] = t("people.refund_receipt.not_created")
      return redirect_to person_deregistration_path(person)
    end

    send_document(receipt)
  end

  # Makes the receipt: stores its day and who made it, which every later PDF
  # reuses, and comes back with the receipt's section open.
  def create_receipt
    Wsjrdp2027::RefundReceipt.new(person, generated_by: current_user).record_creation!(current_user)
    session[SESSION_KEY] = SECTIONS & (remembered_sections | ["receipt"])
    flash[:notice] = t("people.refund_receipt.created")
    redirect_to person_deregistration_path(person)
  end

  # Throws the made receipt away: its day and maker go, and the next PDF is
  # made afresh.
  def discard_receipt
    clear_receipt
    # The person's data stays captured while the form still says it.
    Wsjrdp2027::DeregistrationSnapshot.for(person).clear! unless person.deregistration_form_created_date
    person.save! if person.changed?
    flash[:notice] = t("people.refund_receipt.discarded")
    redirect_to person_deregistration_path(person)
  end

  # Which sections the page has open, written back into the session as one
  # comma-separated list -- there is nothing to answer with. An empty list is a state of its own (everything
  # closed); a key the page does not know is a request nobody's page sent.
  def sections
    return head :unprocessable_entity unless params.key?(:sections)

    keys = params[:sections].to_s.split(",").map(&:strip).compact_blank
    return head :unprocessable_entity unless (keys - SECTIONS).empty?

    session[SESSION_KEY] = SECTIONS & keys
    head :no_content
  end

  def update
    @person ||= person
    @person.attributes = permitted_params
    normalise_flags(permitted_params)
    # What the save is about to write: #save clears it, so it is read here.
    changes = @person.changes
    if !@person.changed?
      answer_update notice: NO_CHANGE_NOTICE
    elsif @person.save
      answer_update notice: change_notice(changes)
    else
      answer_invalid
    end
  end

  private

  # Forgets the made receipt: its day, its maker and its figures.
  def clear_receipt
    person.deregistration_receipt_created_date = nil
    person.deregistration_receipt_created_by_id = nil
    person.deregistration_receipt_snapshot = nil
  end

  # One of the page's two documents, as the request asks for it: page 1 as a PNG
  # for the preview thumbnail (.png), the PDF as a file to save where download
  # says so, and the PDF inline otherwise. Both are built from the person on the
  # spot, so the picture is as good as the data it was drawn from and nothing may
  # keep it.
  def send_document(document)
    if request.format.png?
      response.headers["Cache-Control"] = "private, no-store"
      send_data document.to_png, type: "image/png", disposition: "inline",
        filename: document.file_name.sub(/\.pdf\z/, ".png")
    else
      send_data document.to_pdf, type: "application/pdf",
        disposition: params[:download].present? ? "attachment" : "inline",
        filename: document.file_name
    end
  end

  # Which sections stand open, as they were last left in this session: the
  # first one where nothing is kept, and of a kept list only the keys the page
  # knows (an older deploy's key). A kept empty list means what it says.
  def remembered_sections
    stored = session[SESSION_KEY]
    return DEFAULT_OPEN_SECTIONS unless stored.is_a?(Array)

    SECTIONS & stored.map(&:to_s)
  end

  # Absent is what "show it" looks like in the store, so a checked box clears the
  # key and only an explicit "off" is kept -- as a real false, not the "0" the
  # form carries. A flag the form did not send is left as it stands.
  def normalise_flags(attrs)
    BOOLEAN_ATTRS.each do |attr|
      next unless attrs.key?(attr)

      checked = ActiveModel::Type::Boolean.new.cast(attrs[attr])
      @person.send(:"#{attr}=", checked ? nil : false)
    end
  end

  def authorize_action
    @person ||= person
    @group ||= group
    authorize!(:log, person)
  end

  def permitted_attrs
    [
      :deregistration_kind,
      :deregistration_actual_compensation_cents,
      :deregistration_actual_compensation_eur,
      :deregistration_effective_date,
      :deregistration_form_show_contractual_compensation,
      :deregistration_issue,
      :deregistration_refund_receipt_show_default_explanation,
      :deregistration_refund_receipt_text,
      :deregistration_reply_due_date,
      :deregistration_requested_date
    ]
  end

  def model_params
    params.require(:person)
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end

  def return_url
    return_url_or_fallback person_deregistration_path(person)
  end

  # How a save that went through answers, by what the request asks for: the form
  # inside the capture frame submits as a turbo_stream and gets the three places
  # the save touches (update.turbo_stream), with the person read again so the
  # list and the form show what was stored; anything else gets the redirect.
  def answer_update(notice:)
    respond_to do |format|
      format.turbo_stream do
        @person.reload
        @dereg_saved = true
        @dereg_stay = stay?
        flash.now[:notice] = notice
        render :update
      end
      format.html { redirect_after_update notice: notice }
    end
  end

  # Values the model refused: the form comes back with its errors, in the frame
  # for a turbo_stream request and as the whole page otherwise.
  def answer_invalid
    respond_to do |format|
      format.turbo_stream { render :update, status: :unprocessable_entity }
      format.html { render :edit, status: :bad_request }
    end
  end

  # Whether the save is to hand the form back rather than the list -- what the
  # "Speichern und weiter bearbeiten" button carries.
  def stay?
    params[:stay].present?
  end

  # Where a saved form leads without Turbo: the read-only page, or wherever the
  # form was opened from (the return_url the form carries) -- and back to the
  # form itself where the save is to go on editing.
  def redirect_after_update(notice: nil)
    flash[:notice] = notice if notice.present?
    redirect_to(stay? ? edit_person_deregistration_path(person) : return_url)
  end

  # What the save changed, field by field. The flash partial joins an array with
  # newlines and runs it through simple_format, so each element becomes its own
  # line -- plain text, since the partial sanitizes tags away.
  # A save that changed nothing the page shows (the store shed a value that
  # read as the default) says so, like a save the model saw nothing in.
  def change_notice(changes)
    lines = change_lines(changes)
    return NO_CHANGE_NOTICE if lines.empty?

    ["Angaben zur Abmeldung angepasst:", *lines]
  end

  # In the order this form lists its fields, so the lines do not shuffle from
  # one save to the next.
  def change_lines(changes)
    flat = flat_changes(changes)
    permitted_attrs.filter_map do |attr|
      next unless flat.key?(attr.to_s)

      before, after = flat[attr.to_s]
      "#{change_label(attr)}: " \
        "#{format_change_value(attr, before)} #{CHANGE_ARROW} " \
        "#{format_change_value(attr, after)}"
    end
  end

  # The request date is called after the kind the save leaves behind; every
  # other field by its attribute name.
  def change_label(attr)
    return @person.deregistration_requested_date_label if attr == :deregistration_requested_date

    Person.human_attribute_name(attr)
  end

  # Every deregistration field is a jsonb accessor on additional_info, which
  # Rails tracks as ONE change of that column -- so the per-field before and
  # after have to be read out of the two hashes. A plain column would be tracked
  # on its own and pass through.
  #
  # Either hash can be empty and still carry the change: clearing the last
  # remaining field leaves {} behind, because a blank value drops its key.
  # What decides is whether the column changed at all, not what is left in it.
  def flat_changes(changes)
    flat = changes.except("additional_info")
    return flat unless changes.key?("additional_info")

    before, after = changes["additional_info"]
    before = before.to_h
    after = after.to_h
    (before.keys | after.keys).each do |key|
      next if before[key] == after[key]

      if key.to_s == Wsjrdp2027::DeregistrationRecord::KEY
        flat.merge!(record_changes(before[key], after[key]))
      else
        flat[key] = [before[key], after[key]]
      end
    end
    flat
  end

  # One key of additional_info carries the deregistration record, a hash on
  # each side (Wsjrdp2027::DeregistrationRecord) -- so its change is read per
  # sub-key and named the way permitted_attrs spells it. A side that is missing
  # altogether works like an empty record.
  def record_changes(before, after)
    before = before.to_h.stringify_keys
    after = after.to_h.stringify_keys
    (before.keys | after.keys).each_with_object({}) do |key, changes|
      next if Wsjrdp2027::DeregistrationRecord.same?(key, before[key], after[key])

      changes[Wsjrdp2027::DeregistrationRecord.person_attr(key).to_s] = [before[key], after[key]]
    end
  end

  # The values are the jsonb payload: an ISO string for a date, cents for the
  # amount, free text for the ticket.
  def format_change_value(attr, value)
    sub_key = Wsjrdp2027::DeregistrationRecord.sub_key(attr)
    return Wsjrdp2027::DeregistrationRecord.describe(sub_key, value) if sub_key
    return BLANK_VALUE if value.blank?

    case attr
    when *DATE_ATTRS then I18n.l(value.to_date)
    when *CENTS_ATTRS then format_cents_de(value)
    else value.to_s.squish
    end
  end
end
