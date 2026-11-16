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
#
# The scripts' API (an API key in X-Token, the same :log gate): show.json
# reads the deregistration (Wsjrdp2027::DeregistrationState), create_form.json
# makes the form, form.pdf answers it, and form_sent.json records the mail a
# script sent it with (Wsjrdp2027::DeregistrationFormSent). An API key's
# requests are not asked for a CSRF token, and what they cannot be answered
# with comes back as JSON with status 422 instead of a redirect.
class Person::DeregistrationController < ApplicationController
  include PersonInPrimaryGroup
  include ContractHelper
  include WsjrdpFormHelper

  # Only a request that carries a valid API key skips the check: the check
  # runs before the sign-in, so it asks the token itself -- a bogus one leaves
  # the check in place, and the session behind it stays protected.
  skip_forgery_protection only: [:create_form, :prepare_form, :form_sent, :confirmation_sent],
    if: -> { token_authentication.service_token.present? }

  before_action :authorize_action

  # The form's documents are written as locked changes after the save they
  # belong to (DeregistrationFormDocument, DeregistrationFormSent): while
  # somebody else writes documents, the request is answered with a request to
  # try again -- 503 with code busy for a script, the page's flash otherwise.
  # What was saved before stays saved; doing it again is safe.
  rescue_from Wsjrdp::LockedChange::Busy, ActiveRecord::Deadlocked do
    refuse(t("wsjrdp.documents.create.busy"), code: "busy", status: :service_unavailable)
  end

  helper_method :return_url
  helper_method :permitted_attrs

  # The registration statuses a deregistration that is under way has
  # (prepare_form leaves them as they are).
  NOTED_STATUSES = %w[deregistration_noted deregistered].freeze

  # The slots of the mails kept with a deregistration (#mail_file).
  MAIL_SECONDARY_KEYS = [Wsjrdp2027::DeregistrationFormSent::FORM_MAIL_SECONDARY_KEY, "confirmation_mail"].freeze

  # What the flash's change lines are made of: U+2192 between the two values,
  # an en dash where there is no value. Wsjrdp2027::DeregistrationWording holds
  # the words, so the person log reads like the flash.
  CHANGE_ARROW = Wsjrdp2027::DeregistrationWording::CHANGE_ARROW
  BLANK_VALUE = Wsjrdp2027::DeregistrationWording::BLANK_VALUE
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
    return render(json: Wsjrdp2027::DeregistrationState.new(person)) if request.format.json?

    load_sections
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
      return refuse(helpers.deregistration_form_unavailable_text(form), code: "unavailable")
    end

    # The form is made by #create_form and not before; until then there is no
    # document to show.
    unless form.created?
      return refuse(t("people.deregistration_form.not_created"), code: "form_not_created", status: :conflict)
    end
    # The kept form (DeregistrationFormDocument) and its first page: once it
    # went out the one that was sent, before that the one "PDF erzeugen" or
    # prepare_form.json stored while it still says what the data say. A form
    # with no such PDF is drawn from the data, as it stands.
    stored = request.format.png? ? sent_form_thumbnail_file(form) : sent_form_file(form)
    send_document(form, stored)
  end

  # Makes the form: stores its day, which every later PDF reuses, keeps the
  # PDF as a document of the deregistration (DeregistrationFormDocument) and
  # comes back to the page with the form's section open. Asked for as JSON (a
  # script), it answers the deregistration as it then stands; a form made
  # already stays as it is.
  def create_form
    form = Wsjrdp2027::DeregistrationForm.new(person)
    return prepare_form(note: false) if request.format.json?

    if form.available?
      form.record_creation!
      # A document write is a locked change of its own: after the save.
      Wsjrdp2027::DeregistrationFormDocument.new(person.reload, author: current_user).store!
      session[SESSION_KEY] = SECTIONS & (remembered_sections | ["form"])
      flash[:notice] = t("people.deregistration_form.created")
    else
      flash[:alert] = helpers.deregistration_form_unavailable_text(form)
    end
    redirect_to person_deregistration_path(person)
  end

  # What create_deregistration_form.py asks for before it sends the form, in
  # one go: the registration status moves on to deregistration_noted (unless
  # it is that or deregistered already) -- a save of the person like one on
  # the Status page, so PaperTrail writes it down with the API key --, the
  # form is made where it is not yet, and the answer is the deregistration as
  # it then stands. JSON only (create_form.json is the same without the
  # status).
  #
  # Nothing is written while the form would not be complete
  # (Wsjrdp2027::DeregistrationFormCheck): 422 with every error and warning.
  # Warnings never stand in the way; they come with every answer.
  def prepare_form(note: true)
    return head(:not_acceptable) unless request.format.json?

    check = Wsjrdp2027::DeregistrationFormCheck.new(person)
    if check.errors?
      return api_answer(status: :unprocessable_entity, errors: check.errors, warnings: check.warnings)
    end

    ActiveRecord::Base.transaction do
      if note && !NOTED_STATUSES.include?(person.status)
        person.status = "deregistration_noted"
        person.save!
      end
      Wsjrdp2027::DeregistrationForm.new(person).record_creation!
    end
    # The form as the script will attach it, kept before the answer: the one
    # stored already ("PDF erzeugen", an earlier prepare) where there is one,
    # else stored now. The script fetches exactly this PDF (form.pdf). A
    # document write is a locked change of its own, so after the transaction.
    Wsjrdp2027::DeregistrationFormDocument.new(person.reload, author: current_service_token&.acting_person || current_user,
      service_token: current_service_token).store!
    @person = person.reload
    api_answer(status: :ok, warnings: Wsjrdp2027::DeregistrationFormCheck.new(@person).warnings)
  end

  # Throws the made form away: its day goes, and the next PDF is made -- and
  # dated -- afresh.
  # The receipt goes with it, since it is made from the same captured data,
  # and so do the captured data and the deadline the form fixed. An entered
  # deadline stays.
  # A form that went out stays as it was sent: it is not discarded, a new
  # version (#new_version) takes its place.
  #
  # Under the lock of the row's reports (DeregistrationFormSent.with_report_lock),
  # with the row read anew: a report recorded since the page was loaded has
  # fixed the form, and a report that comes now waits for the discard -- and
  # then finds no form (form_document_missing).
  def discard_form
    Wsjrdp2027::DeregistrationFormSent.with_report_lock(person.deregistration) do
      row = person.deregistration&.reload
      return refuse(t("people.deregistration.fixed"), code: "fixed", status: :conflict) unless person.deregistration_editable?

      discard_form_of(row)
    end
    flash[:notice] = t("people.deregistration_form.discarded")
    redirect_to person_deregistration_path(person)
  end

  # Starts the next version of a deregistration whose form went out
  # (WsjrdpDeregistration#new_version!): what was entered is taken over, the
  # form is made afresh, the old row stays as it was, superseded.
  def new_version
    row = person.deregistration
    return refuse(t("people.deregistration.no_new_version")) if row.nil? || row.editable? || row.final?

    replacement = row.new_version!
    flash[:notice] = t("people.deregistration.new_version_created", number: replacement.number)
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
    person.save!
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

  # A script reports the mail it sent the form with: the API key's only, as
  # JSON (the request body as Wsjrdp2027::DeregistrationFormSent reads it). It
  # answers the deregistration as it then stands, with the recorded mail --
  # 201 for a new one, 200 for a Message-ID recorded already.
  def form_sent = record_mail(Wsjrdp2027::DeregistrationFormSent, "form_mailing")

  # bestätigung_abmeldung.py reports the confirmation it sent
  # (Wsjrdp2027::DeregistrationConfirmationSent), answered like form_sent.
  def confirmation_sent = record_mail(Wsjrdp2027::DeregistrationConfirmationSent, "confirmation_mailing")

  # A mail of the person's deregistration as it went out, as an EML to save:
  # whoever may see this page gets it, whatever the document's own lists say
  # -- the page lists the mail, and the document is the deregistration's.
  def mail_file
    document = deregistration_mail_document(params[:document_id])
    path = document && present_file(document)
    return head(:not_found) unless path

    response.headers["Cache-Control"] = "private, no-store"
    send_file path, type: document.content_type.presence || "message/rfc822", disposition: "attachment",
      filename: document.filename.presence || File.basename(path)
  end

  def update
    @person ||= person
    @person.attributes = permitted_params
    normalise_flags(permitted_params)
    # What the save is about to write: #save clears it, so it is read here --
    # the person's own columns and the deregistration row's values, under the
    # person's names.
    changes = @person.changes.merge(@person.deregistration_changes)
    if changes.empty? && @person.deregistration_input_invalid.empty?
      answer_update notice: NO_CHANGE_NOTICE
    elsif @person.save
      answer_update notice: change_notice(changes)
    else
      answer_invalid
    end
  end

  private

  # What the page's sections draw, for the page and for a save's answer,
  # which redraws them. The page previews what the receipt will say, so it
  # builds the same object the PDF is made of -- and above it, what the
  # creditor the refund is paid to looks like in Moss.
  def load_sections
    @recipients = Wsjrdp2027::DeregistrationMailRecipients.new(@person)
    @refund_creditor = Wsjrdp2027::RefundCreditor.new(@person)
    @refund_receipt = Wsjrdp2027::RefundReceipt.new(@person, generated_by: current_user)
    @deregistration_form = Wsjrdp2027::DeregistrationForm.new(@person)
    @dereg_open_sections = remembered_sections
  end

  # What #discard_form forgets, the row read anew.
  def discard_form_of(row)
    person.deregistration_form_created_date = nil
    person.deregistration_effective_reply_due_date = nil
    clear_receipt
    Wsjrdp2027::DeregistrationSnapshot.for(person).clear!
    row.status = "recorded" if row&.status == "form_created"
    # A form kept for a mail that did not go out is forgotten with it: the
    # row lets go of it (so the page no longer lists it) and it is hidden
    # with its picture; the files stay. The next prepare keeps a new version.
    row.sent_form_document = nil if row && row.form_sent_at.nil?
    person.save!
    # A document write is a locked change of its own: after the save. While
    # the documents are busy the PDF stays current, unlisted, until the next
    # version replaces it -- no reason to fail a discard that is done.
    begin
      Wsjrdp2027::DeregistrationFormDocument.hide_unsent!(person, row, by: current_user)
    rescue Wsjrdp::LockedChange::Busy, ActiveRecord::Deadlocked => e
      Rails.logger.warn("discard_form: the kept form of person #{person.id} was not hidden: #{e.class}: #{e.message}")
    end
  end

  # One of the EMLs of the person's deregistrations (any version of them:
  # key deregistration, a mail's secondary key); nil for anything else.
  def deregistration_mail_document(id)
    WsjrdpDocument.of_subject(person).visible.originals.find_by(id: id.to_i, key: "deregistration",
      secondary_key: MAIL_SECONDARY_KEYS)
  end

  # A mail a script reports: the API key's only, the request body as JSON.
  def record_mail(klass, key)
    return head(:forbidden) unless current_service_token

    payload = begin
      JSON.parse(request.raw_post.presence || "{}")
    rescue JSON::ParserError
      return refuse("the request body is no JSON", code: "bad_json", status: :bad_request)
    end
    sent = klass.new(person, payload, service_token: current_service_token).save!
    @person = person.reload
    api_answer(:status => (sent.duplicate? ? :ok : :created), key => sent.mailing, "duplicate" => sent.duplicate?)
  rescue Wsjrdp2027::DeregistrationFormSent::Invalid => e
    refuse(e.message, code: e.code, status: e.status)
  end

  # Every JSON answer of the scripts' API: the deregistration as it stands
  # (Wsjrdp2027::DeregistrationState, what deregistration.json answers) nested
  # under "deregistration", the errors and warnings ({"code", "message"}
  # each), and what the action adds.
  def api_answer(status:, errors: [], warnings: [], **extra)
    render status: status, json: {
      "deregistration" => Wsjrdp2027::DeregistrationState.new(person).as_json,
      "errors" => errors, "warnings" => warnings
    }.merge(extra.transform_keys(&:to_s))
  end

  # Why something cannot be had or done: for an API key's request (or one
  # asking for JSON) an answer with the reason as its one error -- 422 unless
  # said otherwise --, for the page the reason in the flash and the page
  # itself.
  def refuse(reason, code: "refused", status: :unprocessable_entity)
    if current_service_token || request.format.json?
      api_answer(status: status, errors: [{"code" => code, "message" => reason}])
    else
      flash[:alert] = reason
      redirect_to person_deregistration_path(person)
    end
  end

  # The stored file of the kept form, where there is one to answer: the sent
  # one once the form went out, else the kept one while it is fresh; nil
  # otherwise (the PDF is then drawn from the data). `form` is the request's
  # DeregistrationForm, whose inputs the freshness is judged by -- built once.
  def sent_form_file(form) = present_file(kept_form_document(form))

  def kept_form_document(form)
    row = person.deregistration
    return nil if row.nil?
    return Wsjrdp2027::DeregistrationFormDocument.usable(row.sent_form_document, current: false) if row.form_sent_at

    Wsjrdp2027::DeregistrationFormDocument.new(person, author: nil, form: form).fresh
  end

  # Its first page as a picture, the derivation stored with it.
  def sent_form_thumbnail_file(form)
    document = kept_form_document(form)
    return nil if document.nil?

    present_file(document.derivatives.current.find_by(
      derivation_key: Wsjrdp2027::DeregistrationFormDocument::THUMBNAIL_DERIVATION_KEY
    ))
  end

  def present_file(document)
    return nil if document.nil? || document.file_missing?

    path = Wsjrdp2027::DocumentStore.path_for(document)
    path if File.file?(path)
  end

  # Forgets the made receipt: its day, its maker and its figures.
  def clear_receipt
    person.deregistration_receipt_created_date = nil
    person.deregistration_receipt_created_by_id = nil
    person.deregistration_receipt_snapshot = nil
  end

  # One of the page's two documents, as the request asks for it: page 1 as a PNG
  # for the preview thumbnail (.png), the PDF as a file to save where download
  # says so, and the PDF inline otherwise. `stored` is the kept file of it
  # (the PDF or its picture); without one it is drawn from the person on the
  # spot. Kept by nobody either way: what is answered changes with the data.
  def send_document(document, stored = nil)
    response.headers["Cache-Control"] = "private, no-store"
    png = request.format.png?
    options = {type: png ? "image/png" : "application/pdf",
               filename: png ? document.file_name.sub(/\.pdf\z/, ".png") : document.file_name,
               disposition: (!png && params[:download].present?) ? "attachment" : "inline"}
    return send_file(stored, **options) if stored

    send_data(png ? document.to_png : document.to_pdf, **options)
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
        load_sections
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
  # one save to the next. A value that reads as it did (a stored default and
  # an absent one) has no line.
  def change_lines(changes)
    permitted_attrs.filter_map do |attr|
      next unless changes.key?(attr.to_s)

      before, after = changes[attr.to_s]
      sub_key = Wsjrdp2027::DeregistrationWording.key(attr)
      next if sub_key && Wsjrdp2027::DeregistrationWording.same?(sub_key, before, after)

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

  # The values as the row holds them: a date, cents for the amount, free text
  # for the ticket, the kind and the flags as Wsjrdp2027::DeregistrationWording
  # words them for the log.
  def format_change_value(attr, value)
    sub_key = Wsjrdp2027::DeregistrationWording.key(attr)
    return Wsjrdp2027::DeregistrationWording.describe(sub_key, value) if sub_key
    return BLANK_VALUE if value.blank?

    case attr
    when *DATE_ATTRS then I18n.l(value.to_date)
    when *CENTS_ATTRS then format_cents_de(value)
    else value.to_s.squish
    end
  end
end
