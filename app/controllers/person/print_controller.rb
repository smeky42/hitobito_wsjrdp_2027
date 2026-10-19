# frozen_string_literal: true

class Person::PrintController < ApplicationController
  before_action :authorize_action
  decorates :group, :person

  include ContractHelper

  def index
    group
    @person ||= entry
    # Store what is missing for printing
    @not_printable_reason = not_printable_reason
    @printable = @not_printable_reason.empty?
  end

  def preview
    if printable && (@person.status == "registered")
      @person.ensure_payment_role(rebuild: true)
      @person.save

      pdf = Wsjrdp2027::Export::Pdf::Registration.render(@person, true)

      send_data pdf, type: :pdf, disposition: "attachment", filename: "Anmeldung-WSJ-Vorschau-Nicht-Hochladen.pdf"
    end
  end

  def submit
    if printable && (@person.status == "registered")
      @person.ensure_payment_role(rebuild: true)
      @person.save

      pdf = Wsjrdp2027::Export::Pdf::Registration.new_pdf(@person, false)

      folder = file_folder
      name = file_name
      full_name = folder + name
      FileUtils.mkdir_p(folder) unless File.directory?(folder)

      pdf.render_file full_name

      @person.status = "printed"
      @person.print_at = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
      @person.generated_registration_pdf = full_name
      @person.save

      send_data File.read(full_name), type: :pdf, disposition: "attachment", filename: name
    end
  end

  def not_printable_reason
    reason = ""
    attrs = %w[
      first_name last_name email address zip_code town country
      gender birthday rdp_association_number
    ]

    attrs.each do |attr|
      if @person.public_send(attr).blank?
        reason += "\n - " + I18n.t("activerecord.attributes.person.#{attr}")
      end
    end

    if @person.additional_contact_name_a.blank?
      reason += "\n - #{I18n.t "activerecord.attributes.person.additional_contact_name_a"} #{I18n.t "people.form_tabs.additional_contact_adult"} bzw. #{I18n.t "people.form_tabs.additional_contact_yp"} 1"
    end
    unless @person.additional_contact_single
      if @person.additional_contact_name_b.blank?
        reason += "\n - #{I18n.t "activerecord.attributes.person.additional_contact_name_b"}  #{I18n.t "people.form_tabs.additional_contact_adult"} bzw. #{I18n.t "people.form_tabs.additional_contact_yp"} 2"
      end
    end

    if @person.sepa_name.blank?
      reason += "\n - #{I18n.t "activerecord.attributes.person.sepa_name"} #{I18n.t "activerecord.attributes.person.sepa"}"
    end

    if @person.sepa_address.blank?
      reason += "\n - #{I18n.t "activerecord.attributes.person.sepa_address"} #{I18n.t "activerecord.attributes.person.sepa"}"
    end

    if @person.sepa_mail.blank? || !Truemail.valid?(@person.sepa_mail)
      reason += "\n #{I18n.t "people.alerts.sepa_mail"}"
    end

    if !IBANTools::IBAN.valid?(@person.sepa_iban)
      reason += "\n" + (I18n.t "people.alerts.iban")
    end

    medical_attrs = %i[
      medical_stiko_vaccinations
      medical_additional_vaccinations
      medical_preexisting_conditions
      medical_abnormalities
      medical_allergies
      medical_eating_disorders
      medical_mobility_needs
      medical_infectious_diseases
      medical_medical_treatment_contact
      medical_continuous_medication
      medical_needs_medication
      medical_self_treatment_medication
      medical_mental_health
      medical_situational_support
      medical_person_of_trust
      medical_other
    ]

    all_blank = true
    medical_attrs.each do |attr|
      if !@person.public_send(attr).blank?
        all_blank = false
      end
    end
    if all_blank
      reason += "\n" + (I18n.t "people.alerts.medical")
    end

    reason
  end

  def printable
    not_printable_reason.empty?
  end

  private

  # By id alone, in every group (#group).
  def entry
    @person ||= Person.find(params[:id])
  end

  # The group of the URL, without one the person's default group
  # (Person#default_group, mostly the primary group), as the status page
  # (Person::StatusController#group): the page works in every group and at
  # /people/:id/... in the primary group.
  def group
    @group ||= params[:group_id] ? Group.find(params[:group_id]) : entry.default_group
  end

  def authorize_action
    authorize!(:edit, entry)
  end

  def file_name
    Wsjrdp2027::RegistrationDocuments.generated_registration_filename(@person)
  end

  def file_folder
    # Changed due to problems in container mounting unified with
    # Rails.root.join("private", "uploads", "person", "pdf", @person.id.to_s)
    "#{HitobitoWsjrdp2027::Wagon.root}/private/uploads/person/pdf/#{@person.id}/"
  end
end
