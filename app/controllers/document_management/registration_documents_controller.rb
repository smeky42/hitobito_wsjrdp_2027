# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Anmelde-Dokumente", a tab of the Dokumentenverwaltung in Einstellungen
# (/document_management/registration_documents), for admins: registers the
# registration uploads (people.upload_*_pdf, generated_registration_pdf) as
# documents where their files lie (Wsjrdp2027::RegistrationDocuments).
#
# - index: the counts per key; the chains (one person, one key) as an
#   expandable table over an Array, filtered by the CNF filter in Ruby
#   (DocumentManagement::RegistrationChainsFilterSchema), each with its files
#   as detail; the rights the rows get (those of the kinds,
#   WsjrdpDocumentKind, shown only), the last runs and the findings the scan
#   could not place.
# The form posts to register and names in `operation` what to do (register,
# register_all): its CSRF token is bound to its URL.
#
# - register: registers the chosen chains -- the ids posted, or with
#   select_all every chain the table's filter leaves. Up to SYNC_LIMIT chains
#   at once, more in the background (Wsjrdp2027::RegisterDocumentsJob).
# - progress: what a run in the background is doing, as JSON
#   (Wsjrdp2027::RegisterDocumentsJob.status), for the tab's progress display.
# - cancel: cancels the run in the background (RegisterDocumentsJob.cancel!).
# - register_all: registers every chain not registered as it stands, in the
#   background (Wsjrdp2027::RegisterDocumentsJob).
class DocumentManagement::RegistrationDocumentsController < ApplicationController
  include Wsjrdp::TableStateful
  include Wsjrdp::TrackedJobEndpoints

  STATES = DocumentManagement::RegistrationChainsFilterSchema::STATES
  SYNC_LIMIT = 200
  I18N = "document_management.registration_documents"

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: DocumentManagement::RegistrationChainsColumns::COLUMNS.codec,
    sort: {hidden: [["person", "asc"], ["key", "asc"]]},
    cols: {default: DocumentManagement::RegistrationChainsColumns::COLUMNS.default_keys},
    per_page: {default: 50, max: 200},
    filter: {policy: :url, schema: DocumentManagement::RegistrationChainsFilterSchema,
             presets: DocumentManagement::RegistrationChainsFilterSchema::PRESETS}

  before_action { authorize!(:manage_documents, WsjrdpDocument) }

  helper_method :chains, :table_state, :scan, :kinds, :people_by_id, :counts, :runs

  def index
  end

  def progress = render_tracked_job_status(Wsjrdp2027::RegisterDocumentsJob)

  def cancel
    cancel_tracked_job(Wsjrdp2027::RegisterDocumentsJob,
      back: document_management_registration_documents_path(table_state.wire_params))
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful).
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: document_management_registration_documents_path)
  end

  def register
    return register_all if params[:operation] == "register_all"

    timing = Wsjrdp2027::RegisterDocumentsJob::Timing.new
    chosen = timing.measure(:scan) { chosen_chains }
    return redirect_back_with(alert: t(".nothing_chosen")) if chosen.empty?
    return register_in_background(chosen) if chosen.size > SYNC_LIMIT

    result = timing.measure(:register) { Wsjrdp2027::RegistrationDocuments::Import.new.register(chosen) }
    Wsjrdp2027::RegisterDocumentsJob.log(result, actor_id: current_user.id, run: "ausgewählt", timing: timing.finish)
    flash_key = result.failed.zero? ? :notice : :alert
    redirect_back_with(flash_key => t(".registered", chains: result.chains, created: result.created,
      updated: result.updated, failed: result.failed,
      duration: Wsjrdp2027::RegisterDocumentsJob.format_duration(timing.duration)))
  end

  def register_all
    return redirect_back_with(alert: t("#{I18N}.register_all.running")) if Wsjrdp2027::RegisterDocumentsJob.running?

    Wsjrdp2027::RegisterDocumentsJob.new(current_user.id).enqueue!
    redirect_back_with(notice: t("#{I18N}.register_all.enqueued"))
  end

  private

  def register_in_background(chosen)
    return redirect_back_with(alert: t(".running")) if Wsjrdp2027::RegisterDocumentsJob.running?

    Wsjrdp2027::RegisterDocumentsJob.new(current_user.id, chosen.map(&:id)).enqueue!
    redirect_back_with(notice: t(".enqueued", count: chosen.size))
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # Back to the table as it was (filter, sort, page).
  def redirect_back_with(**flash)
    redirect_to document_management_registration_documents_path(table_state.wire_params), **flash
  end

  # The kinds of the registration uploads, by key.
  def kinds = @kinds ||= Wsjrdp2027::RegistrationDocuments.kinds

  # The posted chain ids, or with select_all every chain of the filter --
  # read from a fresh scan, so the registration sees the files as they are.
  def chosen_chains
    return table_state.filter.scope(named(scan.chains)) if params[:select_all].to_s == "1"

    ids = Array(params[:chain_ids]).map(&:to_s)
    return [] if ids.empty?

    person_ids = ids.map { |id| id.split("-", 2).first.to_i }.uniq
    Wsjrdp2027::RegistrationDocuments::Scan.new(person_ids: person_ids).run.chains
      .select { |chain| ids.include?(chain.id) }
  end

  def scan
    @scan ||= Wsjrdp2027::RegistrationDocuments::Scan.new.run
  end

  # The chains with the names of their people, for the filter and the sort.
  def named(list)
    names = Person.where(id: list.map(&:person_id).uniq)
      .pluck(:id, :first_name, :last_name, :nickname)
      .to_h { |id, first, last, nickname| [id, [[first, last].compact_blank.join(" "), nickname.presence].compact.join(" / ")] }
    list.each { |chain| chain.person_name = names[chain.person_id].to_s }
  end

  # THE table: the chains the filter leaves, sorted and paged by the table's
  # state.
  def chains
    @chains ||= Wsjrdp::ExpandableTableRows.new(table_state,
      table_state.filter.scope(named(scan.chains)),
      sort: DocumentManagement::RegistrationChainsColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(chain) { [chain.person_id, Wsjrdp2027::RegistrationDocuments::KEYS.index(chain.key)] })
  end

  # Per key: chains, files, registered files, missing files; per state the
  # chains.
  def counts
    @counts ||= scan.chains.group_by(&:key).transform_values do |list|
      {chains: list.size, files: list.sum { |chain| chain.entries.size },
       registered: list.sum(&:registered_count), missing: list.sum(&:missing_count),
       states: list.group_by(&:state).transform_values(&:size)}
    end
  end

  # The people of the shown chains and the authors of their files, by id.
  def people_by_id
    @people_by_id ||= begin
      page = chains.page.to_a
      ids = page.map(&:person_id) + page.flat_map do |chain|
        chain.entries.select { |entry| entry.author_type == "Person" }.map(&:author_id)
      end
      Person.where(id: ids.compact.uniq).index_by(&:id)
    end
  end

  def runs
    @runs ||= Wsjrdp2027::RegisterDocumentsJob.entries.order(created_at: :desc).limit(5)
  end
end
