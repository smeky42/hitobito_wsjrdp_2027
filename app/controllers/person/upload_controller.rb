# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class Person::UploadController < ApplicationController
  before_action :authorize_action
  decorates :group, :person

  def index
    @group ||= Group.find(params[:group_id])
    @person ||= group.people.find(params[:id])
    if request.put?
      upload_files
    end
  end

  private

  def entry
    @person ||= Person.find(params[:id])
  end

  def authorize_action
    authorize!(:edit, entry)
  end

  def upload_files
    unless params[:person].nil?
      upload_file(params[:person][:upload_contract_pdf], "upload_contract_pdf")
      upload_file(params[:person][:upload_medical_pdf], "upload_medical_pdf")
      upload_file(params[:person][:upload_data_agreement_pdf], "upload_data_agreement_pdf")
      upload_file(params[:person][:upload_passport_pdf], "upload_passport_pdf")
      upload_file(params[:person][:upload_recommendation_pdf], "upload_recommendation_pdf")
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
      lash[:alert] = I18n.t("activerecord.alert.only_pdf_allowed")
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
