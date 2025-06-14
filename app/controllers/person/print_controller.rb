# frozen_string_literal: true

class Person::PrintController < ApplicationController
  before_action :authorize_action
  decorates :group, :person

  def index
    @group ||= Group.find(params[:group_id])
    @person ||= group.people.find(params[:id])
    @printable = printable

    unless printable
      flash[:alert] = (I18n.t "activerecord.alert.print") + ": " + not_printable_reason
    end

    unless @person.status == "registrered"
      flash[:info] = (I18n.t "activerecord.text.print")
    end
  end

  def preview
    if printable && (@person.status == "registered")
      pdf = Wsjrdp2027::Export::Pdf::Registration.render(@person, true)

      send_data pdf, type: :pdf, disposition: "attachment", filename: "Anmeldung-WSJ-Vorschau-Nicht-Hochladen.pdf"
    end
  end

  def submit
    if printable && (@person.status == "registered")
      pdf = Wsjrdp2027::Export::Pdf::Registration.new_pdf(@person, false)

      folder = file_folder
      name = file_name
      full_name = folder + name
      FileUtils.mkdir_p(folder) unless File.directory?(folder)

      pdf.render_file full_name

      @person.status = "printed"
      @person.generated_registration_pdf = full_name
      @person.save

      send_data File.read(full_name), type: :pdf, disposition: "attachment", filename: name
    end
  end

  def not_printable_reason
    # reason = ""
    # reason
    ""
  end

  def printable
    not_printable_reason.empty?
  end

  private

  def entry
    @person ||= Person.find(params[:id])
  end

  def authorize_action
    authorize!(:edit, entry)
  end

  def file_name
    date = Time.zone.now.strftime("%Y-%m-%d-%H-%M-%S")
    "#{date}--#{@person.id}-registration-generated.pdf"
  end

  def file_folder
    Rails.root.join("private", "uploads", "person", "pdf", @person.id.to_s)
  end
end
