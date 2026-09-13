# frozen_string_literal: true

class Fin::AccountingEntriesController < Fin::FinController
  include WsjrdpFormHelper
  include Fin::AccessHelper
  include FormatHelper
  include UtilityHelper
  include ::ActionView::Helpers::TagHelper

  before_action :authorize_action

  decorates :group, :person

  helper_method :entry

  helper_method :accounting_entry
  helper_method :person
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :selectable_sepa_statuses
  helper_method :hide_subject?
  helper_method :target_turbo_frame

  def entry
    @accounting_entry
  end

  def index
    authorize!(:show, AccountingEntry)
    @accounting_entries = AccountingEntry.limit(20).order(id: "desc")
  end

  def new
    authorize!(:create, AccountingEntry)
    attrs = {amount_currency: "EUR", additional_info: {}}
    attrs.update(permitted_params)
    @accounting_entry = AccountingEntry.new(attrs)
    load_sheet_context
  end

  def new_sepa_status
    authorize!(:create, AccountingEntry)
    attrs = {amount_eur: 0, amount_currency: "EUR", additional_info: {}}
    attrs.update(permitted_params)
    @accounting_entry = AccountingEntry.new(attrs)
    @accounting_entry.author = current_user
    # A status change books nothing: no amount, and out of the fee
    # reconciliation. Both are set here rather than carried in the form, so
    # they hold however the page was reached.
    @accounting_entry.amount_cents = 0
    @accounting_entry.excluded_from_fee_reconciliation = true
    load_sheet_context
    if request.post?
      save_new_sepa_status
    end
  end

  def create
    authorize!(:create, AccountingEntry)
    @accounting_entry = AccountingEntry.new(permitted_params)
    @accounting_entry.author = current_user
    if @accounting_entry.save
      notice = "Neue Buchung in Höhe von #{@accounting_entry.amount_eur_display} € erfolgreich angelegt."
      flash.now[:notice] = notice
      flash.keep
      respond_after_save
    else
      render :new, status: :bad_request
    end
  end

  def show
    @group ||= group
    @person ||= person
    @accounting_entry ||= accounting_entry
    @permitted_attrs ||= permitted_attrs
    render "person/accounting_entries/show"
  end

  def update
    @group ||= group
    @person ||= person
    authorize!(:log, person)
    authorize!(:update, AccountingEntry)
    @accounting_entry ||= accounting_entry
    @permitted_attrs ||= permitted_attrs

    unless params[:accounting_entry].blank?
      accounting_entry.attributes = params.require(:accounting_entry).permit(permitted_attrs)
      unless accounting_entry.save
        render "person/accounting_entries/show", status: :bad_request
        return
      end
    end
    redirect_to return_url
  end

  def destroy
    @accounting_entry ||= accounting_entry
    authorize!(:destroy, @accounting_entry)
    @accounting_entry.destroy!
    redirect_to accounting_group_person_path(group, person)
  end

  def permitted_attrs
    return [] unless can?(:update, AccountingEntry)
    if action_name == "new_sepa_status"
      permitted_attrs_for_new_sepa_status
    elsif (action_name == "new") || (action_name == "create")
      permitted_attrs_for_new_entry
    elsif can?(:admin_finance, AccountingEntry)
      permitted_attrs_for_new_entry
    else
      [:comment]
    end
  end

  # Both new-forms can be opened bare, with nothing in the URL: then there is
  # no accounting_entry key to require, and the form asks for the person
  # itself (f.labeled_person_field :subject).
  def model_params
    params.fetch(:accounting_entry, ActionController::Parameters.new)
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end

  # The sheets around the page (Sheet::Fin::AccountingEntry -> Sheet::Person
  # -> Sheet::Group) read @person and @group from the view. #show sets them
  # too; the two forms for a new entry have to do the same, or the left nav
  # asks a nil group for its layer. It only shows when the page is opened on
  # its own -- inside the turbo frame of the fee page there is no layout.
  # Where a saved form leads. Inside the fee page's turbo frame nothing
  # navigates: that page reloads around the frame, as before. Opened on its
  # own the form IS the page, so it leads to the booking it just created --
  # or back where it came from, if a status change created none. Turbo
  # submits with its own Accept header either way, so the frame header is
  # what tells the two apart, not the response format.
  def respond_after_save
    if turbo_frame_request?
      render turbo_stream: turbo_stream.action(:location_reload, "")
    else
      redirect_to after_save_url(@accounting_entry)
    end
  end

  def after_save_url(entry)
    entry.persisted? ? url_for(entry) : return_url
  end

  def load_sheet_context
    return if accounting_entry.subject_id.blank?

    @person ||= person
    @group ||= group
  end

  def accounting_entry
    @accounting_entry ||= AccountingEntry.find(params[:id])
  end

  def person
    @person ||= accounting_entry.person
  end

  def group
    @group ||= accounting_entry.group
  end

  # The status the person already holds is not a change, so the select does
  # not offer it. save_new_sepa_status still guards the case, for a request
  # that did not come from this form.
  # ?hide_subject=1 leaves the booked person out of the form. The page that
  # opens it says so: on a person's own accounting page the name is right
  # above the frame, and repeating it inside says nothing.
  def hide_subject?
    param_is_true(params, :hide_subject)
  end

  def selectable_sepa_statuses
    statuses = Settings.sepa_status.to_h
    return statuses if accounting_entry.subject_id.blank?

    current = person.sepa_status.to_s
    statuses.reject { |status, _label| status.to_s == current }
  end

  def authorize_action
    authorize!(:show, AccountingEntry)
  end

  private

  def permitted_attrs_for_new_sepa_status
    [
      :amount_cents, :amount_eur,
      :subject_type, :subject_id,
      :description, :comment,
      :new_sepa_status,
      :booking_date, :value_date,
      # Support :excluded_from_fee_reconciliation both flat and
      # nested.
      :excluded_from_fee_reconciliation,
      additional_info: [:excluded_from_fee_reconciliation]
    ]
  end

  def permitted_attrs_for_new_entry
    permitted_attrs_for_new_sepa_status + [
      :pre_notified_amount_cents, :pre_notified_amount_eur,
      :endtoend_id,
      :dbtr_name, :dbtr_iban, :dbtr_bic, :dbtr_address,
      :cdtr_name, :cdtr_iban, :cdtr_bic, :cdtr_address,
      :mandate_id, :mandate_date,
      :debit_sequence_type
    ]
  end

  def save_new_sepa_status
    subject = @accounting_entry.subject
    new_sepa_status = @accounting_entry.new_sepa_status
    # Opened bare, the form asks for both. Neither has a model validation
    # behind it -- an entry without a subject is legitimate, just not as a
    # status change -- so the form says so itself.
    @accounting_entry.errors.add(:subject_id, "muss ausgewählt werden") if subject.nil?
    if new_sepa_status.blank?
      @accounting_entry.errors.add(:new_sepa_status, "muss ausgewählt werden")
    end
    if @accounting_entry.errors.any?
      render :new_sepa_status, status: :bad_request
      return
    end
    if new_sepa_status != subject.sepa_status
      new_sepa_status_msg = "Finanzstatus auf #{Settings.sepa_status[new_sepa_status]} gesetzt"
      @accounting_entry.description = new_sepa_status_msg if @accounting_entry.description.blank?
      ActiveRecord::Base.transaction do
        @accounting_entry.save!
        subject.sepa_status = new_sepa_status
        subject.save!
      end
      if new_sepa_status == "ok"
        flash.now[:notice] = new_sepa_status_msg
      else
        flash.now[:warning] = new_sepa_status_msg
      end
    else
      flash.now[:notice] = "Finanzstatus bleibt #{Settings.sepa_status[new_sepa_status]}"
    end
    flash.keep
    respond_after_save
  rescue ActiveRecord::RecordInvalid
    render :new_sepa_status, status: :bad_request
  end

  def safe_join(array, sep = $OUTPUT_FIELD_SEPARATOR, &block)
    if block
      array = array.collect(&block).compact
    end
    super(array, sep)
  end

  def return_url
    return_url_or_fallback url_for(accounting_entry)
  end

  def cancel_url
    return_url
  end

  def target_turbo_frame
    params[:target_turbo_frame] || :new_accounting_entry_frame
  end
end
