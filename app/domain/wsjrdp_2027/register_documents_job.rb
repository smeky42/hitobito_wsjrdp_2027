# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Registering in the background, for the tab Anmelde-Dokumente
  # (DocumentManagement::RegistrationDocumentsController): every chain of
  # registration uploads that is not registered as it stands ("Alle
  # registrieren"), or the chains of the given ids (a large selection). The
  # log entry, the progress, cancelling and the status are those of every
  # tracked job (Wsjrdp::TrackedJob); this class scans the chains
  # (RegistrationDocuments::Scan) and registers them
  # (RegistrationDocuments::Import), counting people, chains and files. A run
  # over all chains also notes the files of the chains it leaves as they
  # stand as checked (Import#checked).
  class RegisterDocumentsJob < Wsjrdp::TrackedJob
    self.log_category = "documents"
    self.sub_category = "registration_documents_sync"
    self.queue_name = "documents"
    # Next to WsjrdpPaymentReference::GENERATION_LOCK_KEY.
    self.lock_key = 2_027_000_002
    self.i18n_scope = "document_management.registration_documents"
    self.work_phase = "register"
    self.figures = %w[people chains files]
    self.pace = "files"
    self.parameters = Wsjrdp::TrackedJob.parameters + [:chain_ids]

    def initialize(actor_id, chain_ids = nil)
      super(actor_id)
      @chain_ids = chain_ids
    end

    def run_label = @chain_ids ? "ausgewählt, im Hintergrund" : "alle"

    private

    # The chains to register and their totals; those already registered as
    # they stand are only noted as checked (#finish).
    def prepare
      chains = RegistrationDocuments::Scan.new.run.chains
      if @chain_ids
        ids = @chain_ids.to_set
        chains = chains.select { |chain| ids.include?(chain.id) }
      else
        @complete_chains, chains = chains.partition { |chain| chain.state == :complete }
      end
      [chains, {"people" => chains.map(&:person_id).uniq.size, "chains" => chains.size,
                "files" => chains.sum { |chain| chain.entries.size }}]
    end

    def work(chains, progress)
      people = Set.new
      import.register(chains) do |chain, so_far|
        new_person = people.add?(chain.person_id) ? 1 : 0
        progress.tick(so_far, people: new_person, chains: 1, files: chain.entries.size)
      end
    end

    def empty_result = import.register([])

    def finish(_chains) = import.checked(@complete_chains || [])

    def import = @import ||= RegistrationDocuments::Import.new
  end
end
