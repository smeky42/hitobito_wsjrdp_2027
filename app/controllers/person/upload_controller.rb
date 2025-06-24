# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class Person::UploadController < ApplicationController
  before_action :authorize_action
  decorates :group, :person

  include ContractHelper

  def index
    @group ||= Group.find(params[:group_id])
    @person ||= group.people.find(params[:id])
    if request.put?
      upload_files
    end
  end

  def show_contract
    download_file(@person.upload_contract_pdf)
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

  def show_photo_permission_pdf
    download_file(@person.upload_photo_permission_pdf)
  end

  def _good_conduct_pdf
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
    unless params[:person].nil?
      upload_file(params[:person][:upload_contract_pdf], "upload_contract_pdf")
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

    if @person.complete_document_upload_at.nil? &&
        %i[upload_contract_pdf upload_medical_pdf upload_data_agreement_pdf upload_passport_pdf upload_photo_permission_pdf]
            .all? { |fld| @person.public_send(fld).present? }

      if ul?(@person) || ist?(@person) || cmt?(@person)
        if @person.upload_good_conduct_pdf.nil?
          return
        end
      end

      if ul?(@person) || cmt?(@person)
        if @person.upload_data_agreement_pdf.nil?
          return
        end
      end

      if ul?(@person)
        if @person.upload_recommendation_pdf.nil?
          return
        end
      end

      if ul?(person)
        if @person.upload_recommendation_pdf.nil?
          return
        end
      end

      @person.complete_document_upload_at = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
      @person.status = "upload"
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
