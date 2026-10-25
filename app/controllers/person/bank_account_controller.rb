# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Changes the bank account of a person. Optionally also in the
# person's pre notified direct debits
class Person::BankAccountController < ApplicationController
  ATTRS = %i[sepa_name sepa_address sepa_mail sepa_iban sepa_bic sepa_mandate_id sepa_mandate_date].freeze
  DEBIT_ATTRS = {dbtr_name: :sepa_name, dbtr_address: :sepa_address, dbtr_iban: :sepa_iban,
                 dbtr_bic: :sepa_bic}.freeze

  before_action :authorize_action

  helper_method :person, :announced_debits, :comment, :selected_debit_ids, :previous_mandate_date

  def edit
  end

  # Abbrechen in the form: the section's button, back in its place.
  def buttons
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to person_fee_path(person) }
    end
  end

  # The SEPA mandate with the person's current account as a PDF, signed on
  # the mandate date (or `signed_on`); in the browser, or as a download with
  # `download`.
  def mandate
    return head :unprocessable_entity if Wsjrdp2027::SepaMandateRequirements.missing(person).any?

    pdf = Wsjrdp2027::Export::Pdf::Registration.render_sepa_mandate(person, signed_on: signed_on)
    send_data pdf, type: :pdf, filename: "SEPA-Mandat-#{person.id}.pdf",
      disposition: params[:download].present? ? "attachment" : "inline"
  end

  def update
    previous_mandate_date
    person.attributes = account_params
    if [mandate_id_valid?, mandate_date_valid?].all? && save_account
      leave_form
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  private

  def person = @person ||= Person.find(params[:person_id])

  def authorize_action
    authorize!(:update_finance, person)
  end

  def announced_debits
    @announced_debits ||= person.direct_debit_pre_notifications.where(payment_status: "pre_notified").to_a
  end

  # IBAN and BIC without spaces and upper case, as the SEPA files write them;
  # the IBAN is validated by the person (Person#validate_iban_format).
  def account_params
    attrs = params.require(:person).permit(ATTRS)
    %i[sepa_iban sepa_bic].each do |attr|
      attrs[attr] = attrs[attr].to_s.gsub(/\s+/, "").upcase if attrs.key?(attr)
    end
    attrs[:sepa_mandate_id] = attrs[:sepa_mandate_id].to_s.strip.downcase if attrs.key?(:sepa_mandate_id)
    attrs
  end

  def comment = params[:comment].to_s.strip

  # The mandate date before this change; nil for a person never printed.
  def previous_mandate_date
    return @previous_mandate_date if defined?(@previous_mandate_date)

    @previous_mandate_date = person.sepa_mandate_date
  end

  def signed_on
    ActiveModel::Type::Date.new.cast(params[:signed_on].presence) || person.sepa_mandate_date || Time.zone.today
  end

  # Without a form submitted (edit) all announced debits are preselected.
  def selected_debit_ids
    return announced_debits.map(&:id) unless params.key?(:person)

    Array(params[:debit_ids]).map(&:to_i) & announced_debits.map(&:id)
  end

  # A mandate date that is no date would be dropped and fall back to the
  # print of the registration; blank is that on purpose.
  def mandate_date_valid?
    raw = params.dig(:person, :sepa_mandate_date).to_s.strip
    return true if raw.empty? || ActiveModel::Type::Date.new.cast(raw)

    person.errors.add(:sepa_mandate_date, t("people.sepa_account.mandate_date_invalid"))
    false
  end

  def mandate_id_valid?
    return true if Wsjrdp2027::SepaMandateId.valid_for?(person.sepa_mandate_id, person.id)

    person.errors.add(:sepa_mandate_id, t("people.sepa_account.mandate_id_invalid", id: person.id))
    false
  end

  def save_account
    Person.transaction do
      raise ActiveRecord::Rollback unless person.save

      @updated_debits = announced_debits.select { |debit| selected_debit_ids.include?(debit.id) }
      @updated_debits.each { |debit| debit.update!(debit_changes(debit)) }
      Note.create!(subject: person, author: current_user, text: note_text) if comment.present?
      true
    end
  end

  # The account in the debit; the mandate reference only where the viewer may
  # change it there (Fin::DebitEditing: the manage tier).
  def debit_changes(debit)
    changes = DEBIT_ATTRS.transform_values { |attr| person.public_send(attr) }
    changes[:dbtr_iban] = Wsjrdp2027::SepaAccount.iban(person)
    changes[:dbtr_bic] = Wsjrdp2027::SepaAccount.bic(person).presence
    changes[:mandate_date] = person.sepa_mandate_date
    changes[:mandate_id] = person.sepa_mandate_id if can?(:admin_finance, debit)
    changes
  end

  def note_text = "#{t("people.sepa_account.note_prefix")}: #{comment}"

  def leave_form
    notice = if @updated_debits.any?
      t("people.sepa_account.saved_with_debits",
        dates: @updated_debits.map { |debit| I18n.l(debit.collection_date) }.join(", "))
    else
      t("people.sepa_account.saved")
    end
    flash[:bank_account_notice] = {"person_id" => person.id, "text" => notice}
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, nil) }
      format.html { redirect_to person_fee_path(person) }
    end
  end
end
