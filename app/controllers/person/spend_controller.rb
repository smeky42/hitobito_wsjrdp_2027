# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Person::SpendController < ApplicationController
  include PersonInPrimaryGroup

  respond_to :html

  before_action :authorize_action

  helper_method :entry
  helper_method :email_links

  def show
    render :show
  end

  def moss_sso_login
    @person ||= person
    Rails.logger.tagged("#{@person.id} #{@person.short_full_name}") do
      Rails.logger.debug { "Fetch login URL for email #{@person.moss_email}" }
      response = Faraday.get(
        "https://getmoss.com/api/v1/get_login_type", {email: @person.moss_email}
      )
      msgs = [
        "Person: #{@person.id} #{@person.short_full_name}",
        "response.env[:url]: #{response.env[:url]}",
        "response: #{response.inspect}",
        "response.body: #{response.body.inspect}",
        "response.success?: #{response.success?}"
      ]
      msgs.each do |msg|
        Rails.logger.debug { msg }
      end
      if response.success?
        begin
          data = JSON.parse(response.body)
        rescue => exception
          err_msg = "Failed to parse response.body as JSON: #{exception}"
          msgs << err_msg
          Rails.logger.error { err_msg }
          alert_moss_wsj_login_issue(msgs)
          return
        end
        login_link = data["ssoLoginLink"]
        login_type = data["loginType"]
        if login_link.present? && login_type == "SSO_SAML"
          redirect_to login_link, allow_other_host: true
        else
          msgs << "ssoLoginLink: #{login_link.inspect}"
          msgs << "loginType: #{login_type.inspect}"
          alert_moss_wsj_login_issue(msgs)
          return
        end
      else
        alert_moss_wsj_login_issue(msgs)
        return
      end
    end
  end

  private

  def authorize_action
    @person ||= person
    @group ||= group
    authorize!(:edit, @person)
  end

  def entry
    person
  end

  def alert_moss_wsj_login_issue(msgs)
    flash[:alert] = "Abruf des Login-Links fehlgeschlagen. Bitte die folgenden Angaben an einen Admin schicken:\n#{msgs.join("\n")}"
    redirect_to person_spend_path(@person.id)
  end

  def email_links(emails)
    emails.map { |e| helpers.link_to(e, "mailto:#{e}") }.join(", ").html_safe
  end
end
