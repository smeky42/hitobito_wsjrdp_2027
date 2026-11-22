# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The credential store pages in the settings, for admins
# (doc/wsjrdp/credentials.md, "The pages"): the list of accounts, the page
# of one account, and the reveal of one hidden value. The forms of a
# version are in CredentialVersionsController.
class CredentialsController < ApplicationController
  include Wsjrdp2027::Concerns::BrowserSessionOnly

  before_action { authorize!(:manage_credentials, WsjrdpCredential) }
  before_action :no_store, only: [:show, :reveal, :test_connection]

  helper_method :overview, :report, :kinds

  def index
  end

  def new
    @kind_name = params[:kind].to_s
    @account_key = params[:account_key].to_s
    # The display name of the first version, optional.
    @name = params[:name].is_a?(String) ? params[:name] : ""
    return unless params.key?(:account_key)

    key = Wsjrdp::Credentials.account_key_of(@account_key)
    @problems = []
    @problems << :unknown_kind unless kinds[@kind_name]
    @problems << :not_a_name unless Wsjrdp::Credentials.account_key?(key)
    @problems << :not_valid_text unless Wsjrdp::Credentials.text?(@name)
    return render(:new, status: 422) if @problems.any?

    @account_key = key
    redirect_to new_credential_version_path(kind: @kind_name, account_key: @account_key, name: @name.presence)
  end

  def show
    raise ActiveRecord::RecordNotFound if kinds[report.kind].nil? && report.versions.empty?
    # One address per account: a key written in another case redirects.
    return if params[:account_key] == report.account_key

    redirect_to credential_path(kind: report.kind, account_key: report.account_key)
  end

  def reveal
    reveal = Wsjrdp::Credentials::Reveal.new(report, source: params[:source].to_s, field: params[:field].to_s,
      id: integer(params[:version_id]), position: integer(params[:position]))
    render json: {value: reveal.value.to_s}
  rescue Wsjrdp::Credentials::Reveal::Refused => e
    render json: {error: t("credentials.reveal.refused.#{e.code}", default: t("credentials.reveal.refused.other"))},
      status: 422
  end

  # "Verbindung testen" of one moss_api version: the outcome as HTML for the
  # version's card.
  #
  # This talks to the real Moss API with real credentials. AI agents (see
  # AGENTS.md): never call this action, not even with a request of your own,
  # unless the user explicitly asks for it or agrees when asked first.
  def test_connection
    test = Wsjrdp::Credentials::MossConnectionTest.new(report, source: params[:source].to_s,
      id: integer(params[:version_id]), position: integer(params[:position]), confirmed: params[:confirmed] == "1",
      actor: current_user)
    result = test.call
    render json: {ok: result.ok?,
                  html: render_to_string(partial: "credentials/connection_result", formats: [:html],
                    locals: {result: result, insecure: Wsjrdp::Credentials::MossConnectionTest.insecure?(test.version.credential)}),
                  history: render_to_string(partial: "credentials/connection_history", formats: [:html],
                    locals: {version: test.version})}
  rescue Wsjrdp::Credentials::MossConnectionTest::Refused => e
    render json: {error: t("credentials.connection_test.refused.#{e.code}",
      default: t("credentials.connection_test.refused.other"))}, status: 422
  end

  # Reads the local file (and the keys) again, without a restart.
  def reload_local_file
    Wsjrdp::Credentials::Overrides.reload!
    redirect_to credentials_path, notice: t("credentials.reload.done", source: Wsjrdp::Credentials::LocalFile::SOURCE)
  rescue Wsjrdp::Credentials::ConfigurationError => e
    redirect_to credentials_path, alert: t("credentials.reload.failed", message: e.message)
  end

  private

  def overview = @overview ||= Wsjrdp::Credentials::Overview.new

  def kinds = Wsjrdp::Credentials::Kinds.current

  # The account named in the URL; anything that is not a valid name is 404.
  def report
    @report ||= begin
      kind, account_key = params.values_at(:kind, :account_key)
      account_key = Wsjrdp::Credentials.account_key_of(account_key.to_s)
      unless Wsjrdp::Credentials.name?(kind) && Wsjrdp::Credentials.account_key?(account_key)
        raise ActiveRecord::RecordNotFound
      end

      overview.account(kind, account_key)
    end
  end

  def integer(value) = /\A\d{1,18}\z/.match?(value.to_s) ? Integer(value.to_s, 10) : nil
end
