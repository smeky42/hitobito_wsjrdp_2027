# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class Person::UploadController < ApplicationController
  before_action :authorize_action
  decorates :group, :person

  include ContractHelper

  ALL_UPLOAD_ATTRS_SYMS = %i[
    upload_contract_pdf upload_data_agreement_pdf upload_good_conduct_pdf
    upload_medical_pdf upload_passport_pdf upload_photo_permission_pdf
    upload_recommendation_pdf upload_sepa_pdf
  ]

  def index
    @group ||= Group.find(params[:group_id])
    @person ||= group.people.find(params[:id])
    if request.put?
      upload_files
    end
  end

  def show_registration_generated
    # File should exist if not created before docker volume problem
    # generate new if not
    if !File.exist?(@person.generated_registration_pdf)
      pdf = Wsjrdp2027::Export::Pdf::Registration.new_pdf(@person, false)

      folder = generate_file_path
      date = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
      name = "#{date}--#{@person.id}-registration-generated.pdf"
      full_name = folder + name
      FileUtils.mkdir_p(folder) unless File.directory?(folder)

      pdf.render_file full_name

      @person.generated_registration_pdf = full_name
      @person.save
    end
    download_file(@person.generated_registration_pdf)
  end

  def destroy
    @person ||= group.people.find(params[:id])
    unless request.delete? && can?(:log, @person)
      redirect_back_or_to(upload_group_person_path,
        alert: "Du darfst keine Dokumente löschen!")
      return
    end
    what = params[:what].to_sym
    unless ALL_UPLOAD_ATTRS_SYMS.any?(what)
      redirect_back_or_to(upload_group_person_path,
        alert: "Du darfst #{what} nicht löschen!")
      return
    end
    Rails.logger.tagged("#{@person.id} #{@person.short_full_name}") do
      val = @person.send(what)
      Rails.logger.debug { "old value of #{what}: #{val.inspect}" }
      @person.send(:"#{what}=", nil)
      if @person.upload_complete?
        # after deletion still upload_complete? => we are in a special
        # case, e.g., deletion of the good conduct document.
        if what == :upload_good_conduct_pdf && %w[in_review reviewed confirmed].any?(@person.status)
          tag_name = ContractHelper::GOOD_CONDUCT_MISSING_TAG
          Rails.logger.debug ActiveSupport::LogSubscriber.new.send(:color, "Add tag #{tag_name.inspect}", :magenta)
          @person.tag_list.add(tag_name)
        end
      else
        # Upload no longer complete => set status back to "printed"
        @person.status = "printed"
      end
      @person.save!
      val = @person.send(what)
      Rails.logger.debug { "new value of #{what}: #{val.inspect}" }
    end
    redirect_to upload_group_person_path
  end

  def show_contract
    download_file(@person.upload_contract_pdf)
  end

  def show_sepa
    download_file(@person.upload_sepa_pdf)
  end

  def show_medical
    download_file(@person.upload_medical_pdf)
  end

  def show_data_agreement
    download_file(@person.upload_data_agreement_pdf)
  end

  def show_passport
    download_file(@person.upload_passport_pdf)
  end

  def show_recommendation
    download_file(@person.upload_recommendation_pdf)
  end

  def show_photo_permission
    download_file(@person.upload_photo_permission_pdf)
  end

  def show_good_conduct
    download_file(@person.upload_good_conduct_pdf)
  end

  private

  def entry
    @person ||= Person.find(params[:id])
  end

  def authorize_action
    authorize!(:edit, entry)
  end

  def download_file(file)
    if file.present? && can?(:edit, @person)
      file_name = File.basename(file)
      File.open(file, "r") do |f|
        send_data f.read.force_encoding("BINARY"), filename: file_name,
          type: "application/pdf",
          disposition: "inline"
      end
    end
  end

  def upload_files
    Rails.logger.debug "-------------------- Upload"
    unless params[:person].nil?
      upload_file(params[:person][:upload_contract_pdf], "upload_contract_pdf")
      upload_file(params[:person][:upload_sepa_pdf], "upload_sepa_pdf")
      upload_file(params[:person][:upload_medical_pdf], "upload_medical_pdf")
      upload_file(params[:person][:upload_passport_pdf], "upload_passport_pdf")
      upload_file(params[:person][:upload_photo_permission_pdf], "upload_photo_permission_pdf")
      upload_file(params[:person][:upload_good_conduct_pdf], "upload_good_conduct_pdf")
      upload_file(params[:person][:upload_data_agreement_pdf], "upload_data_agreement_pdf")
      upload_file(params[:person][:upload_recommendation_pdf], "upload_recommendation_pdf")
    end
    check_files

    redirect_to upload_group_person_path
  end

  def check_files
    if @person.contract_upload_at.nil? && @person.upload_contract_pdf.present?
      @person.contract_upload_at = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
      @person.save
    end

    if @person.upload_complete?
      if @person.complete_document_upload_at.nil?
        @person.complete_document_upload_at = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
      end
      # Set status to "upload" only if
      # - there is some actual upload
      # - OR the current status is "printed"
      #
      # This way, just clicking "Dokumente hochladen" without having
      # selected any files does not change the status in most cases.
      if !params[:person].nil? || @person.status == "printed"
        @person.status = "upload"
      end
      @person.save
    end
  end

  def upload_file(file_param, file_name)
    if file_param.nil?
      return
    end

    if file_param.content_type == "application/pdf"
      file_path = file_path(file_name)
      FileUtils.mkdir_p(File.dirname(file_path)) unless File.directory?(File.dirname(file_path))
      File.binwrite(file_path, file_param.read)

      @person[file_name] = file_path
      @person.save

    else
      flash[:alert] = I18n.t("activerecord.alert.only_pdf_allowed")
      redirect_to upload_group_person_path
    end
  end

  def file_path(file_name)
    date = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
    file_name = file_name.remove("upload_").remove("_pdf")
    "#{generate_file_path}#{date}--#{@person.id}-#{file_name}.pdf"
  end

  def generate_file_path
    "#{HitobitoWsjrdp2027::Wagon.root}/private/uploads/person/pdf/#{@person.id}/"
  end
end
