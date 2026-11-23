# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The runs of the Synchronisation (doc/fin/sync.md): start one, look at its
# plan, write it, go on after a stop, or cancel it.
class Fin::SyncRunsController < Fin::FinController
  include Fin::SyncTables

  # The run's page shows every part open.
  sync_tables open_parts: -> { @run ? @run.parts.map { |part| part.id.to_s } : [] }, changes_per_page: 50

  before_action { authorize!(:configure_finance, Group) }
  before_action :no_store
  before_action :load_run, except: :create

  # Fetches from Moss and plans; writes nothing yet.
  #
  # This talks to the real Moss API with real credentials. AI agents (see
  # AGENTS.md): never call this action, not even with a request of your own,
  # unless the user explicitly asks for it or agrees when asked first.
  def create
    account_key = params[:account_key].to_s
    raise ActiveRecord::RecordNotFound unless Wsjrdp::Sync::MossApi.account_keys.include?(account_key)

    selection = Array(params[:parts]).map(&:to_s).select { |key| Wsjrdp::Sync.part?(key) }
    return redirect_to(fin_sync_moss_api_path, alert: t("fin.sync.run.no_part")) if selection.empty?

    credential = Wsjrdp::Sync::MossApi.credential(account_key)
    run = Wsjrdp::Sync::Start.new(source: Wsjrdp::Sync::MossApi::KIND, selection: selection, actor: current_user,
      client: Wsjrdp::Sync::MossApi.client(credential), credential: credential,
      credential_source: Wsjrdp::Sync::MossApi.credential_source(account_key)).call
    redirect_to fin_sync_moss_api_run_path(run)
  end

  def show
  end

  def apply
    Wsjrdp::Sync::Apply.new(@run, actor: current_user, confirmed: params[:confirmed] == "1",
      warnings_confirmed: params[:warnings_confirmed] == "1").call
    redirect_to fin_sync_moss_api_run_path(@run), notice: t("fin.sync.run.after_apply.#{@run.status}")
  rescue Wsjrdp::Sync::Apply::Refused => e
    redirect_to fin_sync_moss_api_run_path(@run), alert: t("fin.sync.run.refused.#{e.code}")
  end

  def cancel
    if Wsjrdp::Sync::Cancel.call(@run)
      redirect_to fin_sync_moss_api_run_path(@run), notice: t("fin.sync.run.cancelled")
    else
      redirect_to fin_sync_moss_api_run_path(@run), alert: t("fin.sync.run.refused.not_open")
    end
  end

  # One file of a part, for debugging.
  def file
    entry = @run.parts.flat_map(&:files).find { |candidate| candidate["name"] == params[:name] }
    path = entry && Wsjrdp::Sync::Files.root.join(entry["name"])
    raise ActiveRecord::RecordNotFound unless path && File.file?(path)

    send_file path, type: "application/json", disposition: "attachment"
  end

  private

  def load_run
    @run = WsjrdpSyncRun.find(params[:id])
  end
end
