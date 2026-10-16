# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Dokumentenverwaltung in Einstellungen (Übersicht, Anmelde-Dokumente) and
# the main section Dokumente (Alle, Nach Person und Art, Arten), for admins only.
describe "Dokumentenverwaltung", type: :request do
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }
  let(:folder) { root.join("person/pdf/#{person.id}") }
  let(:name) { "2025-06-28-14-38-32--#{person.id}-medical.pdf" }
  let(:prefix) { "/app-src/vendor/wagons/hitobito_wsjrdp_2027/private/uploads/person/pdf/#{person.id}" }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    FileUtils.mkdir_p(folder)
    folder.join(name).write("%PDF-1.4")
    person.update_columns(upload_medical_pdf: "#{prefix}/#{name}")
  end

  after { FileUtils.rm_rf(root) }

  def html = Capybara.string(response.body)

  # The table's filter (param f) for a CNF tree over the chains.
  def chain_filter(tree)
    schema = DocumentManagement::RegistrationChainsFilterSchema
    schema.encode(Wsjrdp::Filtering::Query.parse(tree), schema: schema.bound)
  end

  %w[/document_management /documents /documents/by_person_and_kind /document_management/registration_documents
    /document_management/document_kinds].each do |path|
    it "refuses #{path} to who is no admin" do
      sign_in(people(:cmt_leader))

      expect { get path }.to raise_error(CanCan::AccessDenied)
    end
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "checks the files of all documents in the background from the overview" do
      document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "deregistration", filename: "a.pdf"})
      Wsjrdp2027::DocumentStore.path_for(document).delete

      get "/document_management"
      expect(html).to have_button("Alle Dateien prüfen (im Hintergrund)")
      box = html.find("#document-file-check-progress", visible: :all)
      expect(JSON.parse(box["data-status"])).to include("state" => "idle")

      expect { post "/document_management/check_files" }.to change(Delayed::Job, :count).by(1)
      expect(flash[:notice]).to include("Hintergrund")
      expect(Delayed::Job.last.queue).to eq("documents")
      get "/document_management/check_files/progress"
      expect(response.parsed_body).to include("state" => "waiting")
      post "/document_management/check_files"
      expect(flash[:alert]).to include("läuft bereits")

      job = Delayed::Job.last.payload_object
      Delayed::Job.delete_all
      job.perform
      expect(document.reload.file_status).to eq("missing")
      entry = Wsjrdp2027::CheckDocumentFilesJob.entries.last
      expect(entry.payload).to include("status" => "finished", "totals" => {"files" => 1}, "done" => {"files" => 1},
        "missing" => 1)
      expect(entry.message).to include("1 geprüft, 1 jetzt fehlend")

      get "/document_management"
      expect(html).to have_css("#document-file-check-runs", text: "1 jetzt fehlend")
    end

    it "takes a waiting file check out of the queue" do
      post "/document_management/check_files"

      expect { post "/document_management/check_files/cancel", as: :json }.to change(Delayed::Job, :count).by(-1)
      expect(response.parsed_body).to include("outcome" => "dequeued", "state" => "idle", "last_status" => "cancelled")
    end

    it "shows the Dokumentenverwaltung in Einstellungen with its tabs" do
      %w[/document_management /document_management/registration_documents].each do |path|
        get path

        expect(response).to have_http_status(200)
        expect(html).to have_css(".nav-left-section.active > a", text: "Einstellungen")
        expect(html).to have_css(".nav-left-section.active li.is-active a[href='/document_management']",
          text: "Dokumentenverwaltung")
        expect(html).to have_link("Übersicht", href: "/document_management")
        expect(html).to have_link("Anmelde-Dokumente", href: "/document_management/registration_documents")
        expect(html).not_to have_link("Arten", href: "/document_management/document_kinds")
      end
    end

    it "shows the main section Dokumente with its tabs" do
      %w[/documents /documents/by_person_and_kind /document_management/document_kinds].each do |path|
        get path

        expect(response).to have_http_status(200)
        expect(html).to have_css(".nav-left-section.active > a[href='/documents']", text: "Dokumente")
        expect(html).to have_link("Alle", href: "/documents")
        expect(html).to have_link("Nach Person und Art", href: "/documents/by_person_and_kind")
        expect(html).to have_link("Arten", href: "/document_management/document_kinds")
        expect(html).not_to have_link("Anmelde-Dokumente", href: "/document_management/registration_documents")
      end
    end

    it "lists every document and shows one" do
      document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "deregistration", filename: "brief.pdf"})
      Wsjrdp2027::DocumentStore.hide!(document)

      get "/documents"
      expect(response).to have_http_status(200)
      expect(html).to have_css("turbo-frame#bkframe-doc-#{document.id}", visible: :all)

      get "/documents/#{document.id}/details"
      expect(response).to have_http_status(200)
      expect(html).to have_css("#document-fields", text: "gelöscht")
    end

    it "shows each document's kind, unknown without one, and filters by it" do
      known = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 a"),
        {subject: person, key: "medical", filename: "medizin.pdf"})
      unknown = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 b"),
        {subject: person, key: "deregistration", filename: "brief.pdf"})
      schema = DocumentManagement::DocumentsFilterSchema
      filter = ->(value) {
        schema.encode(Wsjrdp::Filtering::Query.parse([[["kind", "in", value]]]), schema: schema.bound)
      }

      get "/documents"
      expect(html).to have_css("td.dmcol-kind a[title*='Schlüssel: medical']", text: "Medizinbogen")
      expect(html).to have_css("td.dmcol-kind span[title*='Schlüssel: deregistration']", text: "unbekannt")
      expect(html).to have_css("td.dmcol-status span.text-success", text: "aktuell")
      expect(html).to have_css("td.dmcol-file_status span[title='vorhanden'] .text-muted")

      unknown.update_columns(file_status: WsjrdpDocument::FILE_MISSING)
      get "/documents"
      expect(html).to have_css("td.dmcol-file_status span[title='fehlt'] .text-danger")

      get html.find(".flt-presets a", text: "Datei fehlt")[:href]
      expect(html).to have_css("turbo-frame#bkframe-doc-#{unknown.id}", visible: :all)
      expect(html).not_to have_css("turbo-frame#bkframe-doc-#{known.id}", visible: :all)

      get "/documents", params: {f: filter.call("medical")}
      expect(html).to have_css("turbo-frame#bkframe-doc-#{known.id}", visible: :all)
      expect(html).not_to have_css("turbo-frame#bkframe-doc-#{unknown.id}", visible: :all)

      expect(WsjrdpDocumentKind.new(key: "deregistration", secondary_key: "signed_form").keys_path)
        .to eq("deregistration/signed_form")
      expect(wsjrdp_document_kinds(:medical).keys_path).to eq("medical")

      get "/documents", params: {f: filter.call("_unknown")}
      expect(html).to have_css("turbo-frame#bkframe-doc-#{unknown.id}", visible: :all)
      expect(html).not_to have_css("turbo-frame#bkframe-doc-#{known.id}", visible: :all)
    end

    it "groups the documents by person and kind, whatever their numbers, and links each group" do
      first = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 a"),
        {subject: person, key: "deregistration", key_number: 1, filename: "a.pdf"})
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 b"),
        {subject: person, key: "deregistration", key_number: 1, filename: "b.pdf", replaces: first})
      second = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 c"),
        {subject: person, key: "deregistration", key_number: 2, filename: "c.pdf"})
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 d"),
        {subject: people(:yp_a_2), key: "deregistration", key_number: 1, filename: "d.pdf"})

      get "/documents/by_person_and_kind", params: {c: "sj,kd,k,sk,n,cu,su,de,mi,la"}
      expect(response).to have_http_status(200)
      expect(html).to have_css("h1", text: "Nach Person und Art")
      expect(html).to have_css("li.active a[href='/documents/by_person_and_kind']", text: "Nach Person und Art")
      expect(html.all("tbody tr", text: /deregistration/).size).to eq(2)
      mine = html.find("tbody tr", text: /#{Regexp.escape(person.to_s)}.*deregistration/m)
      expect(mine.all("td").map { |td| td.text.squish }).to include("unbekannt", "deregistration", "3", "2/2 ✓")
      expect(mine).to have_css("td.dgcol-current span[title^='Alle 2 Kombinationen'] .text-muted")

      # One combination without a current document: some.
      Wsjrdp2027::DocumentStore.hide!(second)
      get "/documents/by_person_and_kind", params: {c: "sj,kd,k,sk,n,cu,su,de,mi,la"}
      mine = html.find("tbody tr", text: /#{Regexp.escape(person.to_s)}.*deregistration/m)
      expect(mine).to have_css("td.dgcol-current span[title^='1 von 2'] .text-warning", text: "")
      expect(mine.find("td.dgcol-current").text.squish).to eq("1/2")

      param = "person-#{person.id}-deregistration"
      expect(html).to have_css("turbo-frame#bkframe-dgr-#{param}[src*='/documents/by_person_and_kind/#{param}?']",
        visible: :all)

      get "/documents/by_person_and_kind/#{param}"
      expect(html).to have_css("h1", text: "#{person} · unbekannt")
      expect(html).to have_css("li.active a[href='/documents/by_person_and_kind']", text: "Nach Person und Art")
      expect(html).to have_css("#document-group-fields", text: "3 (aktuell 1 · ersetzt 1 · gelöscht 1)")
      versions = html.all(".document-versions-table tr.exp-row")
      expect(versions.map { |tr| tr.find("td.dvcol-numbers").text.squish })
        .to eq(%w[deregistration-1 deregistration-1 deregistration-2])
      # Each version opens the document's page without its versions.
      expect(html).to have_css(".document-versions-table turbo-frame[src*='versions=none']", visible: :all)
      version_src = html.find(".document-versions-table turbo-frame", match: :first, visible: :all)[:src]

      get html.first("#document-group-actions a")[:href]
      expect(html).to have_css("#documents-shown", text: "3 Dokumente")
      expect(html).to have_css("li.active a[href='/documents']", text: "Alle")

      get version_src
      expect(html).to have_css("h1", text: "Dokument")
      expect(html).not_to have_css(".document-versions-table")
    end

    it "shows a group's versions in Alle by person and kind" do
      document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "medical", filename: "m.pdf", content_type: "application/pdf"})

      get "/documents/by_person_and_kind/person-#{person.id}-medical"
      href = html.first("#document-group-actions a")[:href]
      expect(html.find("#document-group-actions a[target=_blank]")[:href]).to eq(href)
      expect(CGI.unescape(href)).to include("(kd,in,'medical')").and include("(sid,in,'#{person.id}')")
      expect(CGI.unescape(href)).not_to include("(k,in,")

      get href
      expect(html).to have_css("turbo-frame#bkframe-doc-#{document.id}", visible: :all)
    end

    it "shows the page links as the columns menu says: auto, always or never" do
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "medical", filename: "m.pdf", content_type: "application/pdf"})

      # The detail's "Detailseite" is the page column's fallback: shown while
      # the column is not, by the table's marker styles.
      fallback = ".exp-detail-linkbar[data-exp-if-any-hidden] .exp-fallback[data-exp-if-hidden='_page'] .exp-detail-links"
      marker = ->(rule) { html.all("style", visible: :all).map { |style| style.text(:all) }.join.include?(rule) }

      get "/documents/by_person_and_kind"
      expect(html).to have_css("td[data-colkey=_page] .exp-page-link")
      expect(html).to have_css(fallback, visible: :all)
      expect(marker.call("(width >= ")).to be true
      expect(html).to have_css("button.exp-cols-links[aria-checked=mixed][data-links-next='_l']", text: "auto",
        visible: :all)

      get "/documents/by_person_and_kind", params: {c: "sj,kd,_l"}
      expect(html).to have_css("td[data-colkey=_page] .exp-page-link")
      expect(marker.call(".exp-detail [data-exp-if-any-hidden] { display: none !important; }")).to be true

      get "/documents/by_person_and_kind", params: {c: "sj,kd,~_l"}
      expect(html).not_to have_css("td[data-colkey=_page]")
      expect(html).to have_css(fallback, visible: :all)
      expect(marker.call("[data-exp-if-any-hidden] { display")).to be false
      expect(html).to have_css("button.exp-cols-links[aria-checked=false][data-links-next='_l.a']", text: "nie",
        visible: :all)

      # No data column: a hint, and the columns menu to tick some again.
      get "/documents/by_person_and_kind", params: {c: "~sj"}
      expect(html).to have_css(".exp-no-columns", text: "Keine Spalten ausgewählt")
      expect(html).to have_css(".exp-tools .exp-cols-form", visible: :all)
      expect(html).not_to have_css("table.bookings-table")
    end

    it "answers 404 for a group parameter that is not canonical or names no documents" do
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "deregistration", filename: "a.pdf"})

      get "/documents/by_person_and_kind/person-#{person.id}-deregistration"
      expect(response).to have_http_status(200)
      ["person-#{person.id}-deregistration-1", "Person-#{person.id}-deregistration",
        "group-#{person.id}-deregistration", "person-#{person.id}-medical"].each do |param|
        expect { get "/documents/by_person_and_kind/#{param}" }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "orders the groups by the latest upload, then by person, then by the kind's position" do
      other = people(:yp_a_2)
      at = 2.days.ago.beginning_of_minute
      [[person, "medical"], [person, "contract"], [person, "deregistration"], [other, "sepa"], [other, "passport"]]
        .each_with_index do |(subject, key), i|
          document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 #{i}"),
            {subject: subject, key: key, filename: "#{i}.pdf"})
          document.update_columns(created_at: (key == "passport") ? at + 1.hour : at)
        end
      expect(person.to_s.downcase).to be < other.to_s.downcase

      get "/documents/by_person_and_kind", params: {s: "", c: "sj,kd,k,sk,n,cu,su,de,mi,la"}
      rows = html.all("tbody tr").map { |tr| tr.all("td.dgcol-key").map(&:text).first.to_s.squish }.compact_blank
      expect(rows & %w[medical contract deregistration sepa passport])
        .to eq(%w[passport contract medical deregistration sepa])
    end

    it "counts only the filtered documents in a group" do
      first = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 a"),
        {subject: person, key: "deregistration", filename: "a.pdf"})
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 b"),
        {subject: person, key: "deregistration", filename: "b.pdf", replaces: first})
      schema = DocumentManagement::DocumentsFilterSchema
      current = schema.encode(Wsjrdp::Filtering::Query.parse([[%w[status in current]]]), schema: schema.bound)

      get "/documents/by_person_and_kind", params: {f: current, c: "sj,kd,k,sk,n,cu,su,de,mi,la"}
      expect(html.find("tr", text: /deregistration/).all("td").map { |td| td.text.squish })
        .to include("deregistration", "1")
      expect(html).not_to have_css("tr", text: /deregistration\s+2/)
    end

    it "orders by the newest upload, then the highest id, after any chosen sort" do
      # The oldest upload has the highest id, so only the upload time puts it last.
      newer, newest, older = 3.times.map do |i|
        Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 #{i}"),
          {subject: person, key: "deregistration", key_number: i, filename: "#{i}.pdf"})
      end
      older.update_columns(created_at: 2.days.ago)
      [newer, newest].each { |document| document.update_columns(created_at: 1.day.ago.beginning_of_minute) }
      ids = -> { html.all("turbo-frame[id^='bkframe-doc-']", visible: :all).map { |f| f[:id].delete_prefix("bkframe-doc-").to_i } }

      get "/documents", params: {s: ""}
      expect(ids.call & [older.id, newer.id, newest.id]).to eq([newest.id, newer.id, older.id])

      get "/documents", params: {s: "kd"}
      expect(ids.call & [older.id, newer.id, newest.id]).to eq([newest.id, newer.id, older.id])
    end

    it "compares two versions only once both are picked" do
      first = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 a"),
        {subject: person, key: "deregistration", filename: "brief.pdf", content_type: "application/pdf"})
      second = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 b"),
        {subject: person, key: "deregistration", filename: "brief.pdf", content_type: "application/pdf", replaces: first})
      preview = "document-preview-#{second.id}"

      get "/documents/#{second.id}/details"
      rows = html.all(".document-versions-table tr.exp-row")
      expect(rows.map { |tr| tr.find("td.dvcol-id").text }).to eq([second.id.to_s, first.id.to_s])
      expect(rows.first[:class]).to include("table-active")
      expect(rows.last).to have_css("div[title^='ersetzt am'] .text-muted i.fa-level-up-alt")
      expect(html).to have_css(".document-versions-table thead a", text: "Ersetzt")
      expect(html).to have_css(".document-versions-table thead a", text: "gelöscht")
      expect(html).to have_css(".document-versions-table turbo-frame[src*='versions=none']", visible: :all)
      expect(html).not_to have_css(".document-versions-table input[name^='#{preview}'][checked]")
      expect(html).to have_css("section##{preview}[hidden]", visible: :all)
      expect(html).to have_css("##{preview} template[data-doc='#{first.id}']", visible: :all)
      expect(html).to have_css("button.document-preview-toggle[data-bs-target='#document-file-preview-#{second.id}']")
      expect(html).to have_css("#document-file-preview-#{second.id} iframe[data-src='/documents/#{second.id}']:not([src])",
        visible: :all)

      get "/documents/#{second.id}/details", params: {left: second.id, right: first.id}
      expect(html).to have_css(".document-versions-table input[name='#{preview}-left'][value='#{second.id}'][checked]")
      expect(html).to have_css(".document-versions-table input[name='#{preview}-right'][value='#{first.id}'][checked]")
      expect(html).to have_css("section##{preview}:not([hidden])")
    end

    it "links the author like any person and marks one that is gone" do
      document = Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"),
        {subject: person, key: "deregistration", filename: "brief.pdf", author: admin})

      get "/documents/#{document.id}/details"
      expect(html).to have_link(admin.to_s, href: "/people/#{admin.id}")
      expect(html).not_to have_css("#document-fields", text: "(#{admin.id})")

      document.update_columns(author_id: Person.maximum(:id) + 1)
      get "/documents/#{document.id}/details"
      expect(html).to have_css("#document-fields", text: "Person #{document.author_id} (nicht gültig)")
    end

    it "shows the chains of the registration uploads, filtered by the CNF filter" do
      get "/document_management/registration_documents", params: {f: chain_filter([[["person_id", "eq", person.id]]])}

      expect(response).to have_http_status(200)
      expect(html).to have_css("tr.exp-row span[title='medical']", text: "Medizinbogen")
      expect(html).to have_css("tr.exp-row", text: "nicht registriert")
      expect(html).to have_css("#registration-documents-shown", text: "1 Kette")

      get "/document_management/registration_documents", params: {f: chain_filter([[%w[state in complete]]])}
      expect(html).to have_css("#registration-documents-shown", text: "0 Ketten")
      expect(html).to have_css("#registration-documents-rights tr", text: /medical\s+person, update\s+log\s+log/,
        visible: :all)
      expect(html).to have_no_field("rights[medical][readable_by][]", visible: :all)
    end

    it "registers the chosen chains with the rights of their kinds and logs the run" do
      post "/document_management/registration_documents/register",
        params: {chain_ids: ["#{person.id}-medical"],
                 rights: {medical: {readable_by: ["", "finance"]}}}

      expect(response).to redirect_to(%r{/document_management/registration_documents})
      document = WsjrdpDocument.of_subject(person).sole
      expect(document).to have_attributes(key: "medical", status: "current", origin: "import",
        readable_by: %w[person update], writable_by: %w[log], deletable_by: %w[log])
      entry = Wsjrdp2027::RegisterDocumentsJob.entries.last
      expect(entry.payload).to include("sub_category" => "registration_documents_sync")
      expect(entry.message).to include("1 Ketten").and include("Dauer")
      expect(entry.payload).to include("duration_seconds", "started_at", "finished_at")
      expect(entry.payload["phase_seconds"].keys).to contain_exactly("scan", "register")
      expect(flash[:notice]).to match(/\(\d+ ms\)|\(\d+,\d s\)/)
    end

    context "with forgery protection, as in production" do
      around do |example|
        protection = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = protection
      end

      # The form's CSRF token is bound to the form's URL, so every button posts
      # there and names its operation.
      %w[register register_all].each do |operation|
        it "accepts the form's token for #{operation}" do
          get "/document_management/registration_documents"
          form = html.find("form#registration-documents-form")
          token = form.find("input[name=authenticity_token]", visible: false).value
          expect(form).to have_button(name: "operation", value: operation)

          post form[:action], params: {authenticity_token: token, operation: operation,
                                       chain_ids: ["#{person.id}-medical"]}

          expect(response).to have_http_status(:redirect)
        end
      end
    end

    it "reports the progress of a run in the background" do
      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "idle")

      post "/document_management/registration_documents/register", params: {operation: "register_all"}
      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "waiting")

      Delayed::Job.last.update_columns(locked_at: 3.seconds.ago, locked_by: "spec")
      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "running", "phase" => "unknown")
      Delayed::Job.last.update_columns(locked_at: nil, locked_by: nil)

      job = Delayed::Job.last.payload_object
      Delayed::Job.delete_all
      # The run takes over the entry written as it was queued.
      expect { job.perform }.not_to change(HitobitoLogEntry.where(category: "documents"), :count)
      entry = HitobitoLogEntry.where(category: "documents").last
      expect(entry.payload).to include("status" => "finished", "totals" => include("people" => 1, "files" => 1),
        "done" => include("people" => 1, "chains" => 1, "files" => 1))

      entry.update_columns(payload: entry.payload.merge("status" => "running", "phase" => "register",
        "work_started_at" => 10.seconds.ago.iso8601, "done" => {"people" => 0, "files" => 1},
        "totals" => {"people" => 1, "files" => 4}), updated_at: Time.current)
      # A running entry without a process holding the run lock: the run died.
      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "stale")

      Wsjrdp2027::RegisterDocumentsJob.with_run_lock do
        get "/document_management/registration_documents/progress"
        expect(response.parsed_body).to include("state" => "running", "remaining_seconds" => be_between(25, 35))
      end
    end

    it "says so when the worker threw a queued run away before it started" do
      post "/document_management/registration_documents/register", params: {operation: "register_all"}
      entry = HitobitoLogEntry.where(category: "documents").last
      expect(entry.payload).to include("status" => "queued", "delayed_job_id" => Delayed::Job.last.id)
      expect(entry.message).to include("eingereiht")

      # What a worker does with a job whose class it does not know.
      Delayed::Job.delete_all
      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "lost", "entry_id" => entry.id)

      get "/document_management/registration_documents"
      box = html.find("#registration-documents-progress", visible: :all)
      expect(box[:hidden]).to be_nil
      expect(JSON.parse(box["data-texts"])["lost"]).to include("neu gestartet")
    end

    it "takes a waiting run out of the queue" do
      post "/document_management/registration_documents/register", params: {operation: "register_all"}

      expect { post "/document_management/registration_documents/cancel", as: :json }
        .to change(Delayed::Job, :count).by(-1)
      expect(response.parsed_body).to include("outcome" => "dequeued", "state" => "idle", "last_status" => "cancelled")
      expect(HitobitoLogEntry.where(category: "documents").last.message).to include("bevor sie begann")
    end

    it "stops a running run after the chain at hand" do
      second = people(:yp_a_2)
      second_folder = root.join("person/pdf/#{second.id}")
      FileUtils.mkdir_p(second_folder)
      second_name = "2025-06-28-14-38-32--#{second.id}-medical.pdf"
      second_folder.join(second_name).write("%PDF-1.4")
      second.update_columns(upload_medical_pdf: "/x/private/uploads/person/pdf/#{second.id}/#{second_name}")
      job = Wsjrdp2027::RegisterDocumentsJob.new(admin.id)
      # Cancelled as soon as the first chain is done.
      allow_any_instance_of(Wsjrdp::TrackedJob::Progress).to receive(:tick).and_wrap_original do |m, *args, **counts|
        Wsjrdp2027::RegisterDocumentsJob.cancel!(by: admin)
        m.receiver.instance_variable_set(:@written_at, nil)
        m.call(*args, **counts)
      end

      job.perform

      entry = HitobitoLogEntry.where(category: "documents").last
      expect(entry.payload).to include("status" => "cancelled", "cancel_requested_by" => admin.id,
        "done" => include("chains" => 1), "totals" => include("chains" => 2))
      expect(entry.message).to include("abgebrochen von").and include("nach 1 von 2 Personen")
      expect(WsjrdpDocument.where(origin: "import").count).to eq(1)

      get "/document_management/registration_documents/progress"
      expect(response.parsed_body).to include("state" => "idle", "last_status" => "cancelled")
    end

    it "runs once at a time and logs a run it skips" do
      job = Wsjrdp2027::RegisterDocumentsJob.new(admin.id)
      other = ActiveRecord::Base.connection_pool.checkout
      other.select_value("SELECT pg_advisory_lock(#{Wsjrdp2027::RegisterDocumentsJob.lock_key})")

      expect(Wsjrdp2027::RegisterDocumentsJob.run_alive?).to be(true)
      job.perform
      expect(HitobitoLogEntry.where(category: "documents").last.message).to include("übersprungen")
      expect(WsjrdpDocument.where(origin: "import")).to be_empty
    ensure
      other&.select_value("SELECT pg_advisory_unlock(#{Wsjrdp2027::RegisterDocumentsJob.lock_key})")
      ActiveRecord::Base.connection_pool.checkin(other) if other
    end

    it "keeps a cancel mark the job's progress writes over" do
      entry = HitobitoLogEntry.create!(category: "documents", level: "info", message: "x", subject: admin,
        payload: {"sub_category" => "registration_documents_sync", "status" => "running"})
      Wsjrdp2027::RegisterDocumentsJob.cancel!(by: admin)
      progress = Wsjrdp::TrackedJob::Progress.new(entry, {}, Wsjrdp::TrackedJob::Timing.new,
        Wsjrdp2027::RegisterDocumentsJob)

      expect(progress.write(Wsjrdp2027::RegistrationDocuments::Import.new.register([]))).to be(true)
      expect(entry.reload.payload).to include("cancel_requested_by" => admin.id, "status" => "running")
      Wsjrdp2027::RegisterDocumentsJob.with_run_lock do
        get "/document_management/registration_documents/progress"
        expect(response.parsed_body).to include("state" => "running", "cancelling" => true)
      end
    end

    it "shows the progress box while a run waits" do
      post "/document_management/registration_documents/register", params: {operation: "register_all"}
      get "/document_management/registration_documents"

      box = html.find("#registration-documents-progress", visible: :all)
      expect(box[:hidden]).to be_nil
      expect(JSON.parse(box["data-status"])).to include("state" => "waiting")
    end

    it "registers all in the background" do
      expect { post "/document_management/registration_documents/register_all" }
        .to change(Delayed::Job, :count).by(1)
      expect(flash[:notice]).to include("Hintergrund")
      expect(Delayed::Job.last.queue).to eq("documents")

      Delayed::Job.last.payload_object.perform
      expect(WsjrdpDocument.of_subject(person).count).to eq(1)
      payload = HitobitoLogEntry.where(category: "documents").last.payload
      expect(payload["created"]).to be >= 1
      expect(payload).to include("enqueued_at", "waited_seconds", "duration_seconds")
    end

    it "registers every chain of the filter with select_all, a large selection in the background" do
      filter = chain_filter([[["person_id", "eq", person.id]]])
      post "/document_management/registration_documents/register", params: {select_all: "1", f: filter}

      expect(response).to redirect_to(%r{f=})
      expect(WsjrdpDocument.of_subject(person).count).to eq(1)

      stub_const("DocumentManagement::RegistrationDocumentsController::SYNC_LIMIT", 0)
      expect { post "/document_management/registration_documents/register", params: {select_all: "1", f: filter} }
        .to change(Delayed::Job, :count).by(1)
      expect(Delayed::Job.last.payload_object.instance_variable_get(:@chain_ids)).to eq(["#{person.id}-medical"])
    end

    it "lists only its own runs among the entries of the category" do
      HitobitoLogEntry.create!(category: "documents", level: "info", message: "Anderer Eintrag", subject: admin,
        payload: {"sub_category" => "other"})
      post "/document_management/registration_documents/register", params: {chain_ids: ["#{person.id}-medical"]}
      get "/document_management/registration_documents"

      expect(html).to have_css("#registration-documents-runs tr", count: 1)
      expect(html).to have_no_css("#registration-documents-runs", text: "Anderer Eintrag")
    end
  end

  describe "Dokument-Arten" do
    before { sign_in(admin) }

    let(:medical) { wsjrdp_document_kinds(:medical) }
    let(:form) do
      {label: "Brief", subject_type: "Person", key: "brief", secondary_key: "", position: "100",
       readable_by: ["", "person", "log"], writable_by: ["", "log"], deletable_by: ["", "log"],
       content_types: ["", "application/pdf", "image/*"], extensions: [""], max_upload_size_mb: "5",
       rules: {"n7" => {roles: ["", "UL"], offer_to: ["", "update"], not_for_status: [""], required: "1",
                        missing_tag: "", missing_tag_from_status: [""]},
               "0" => {roles: [""], offer_to: ["", "log"], not_for_status: ["", "registered"],
                       missing_tag: "Brief-fehlt", missing_tag_from_status: ["", "reviewed"], remove_on_upload: "1"},
               "1" => {roles: [""], offer_to: [""], not_for_status: [""], missing_tag: "",
                       missing_tag_from_status: [""]}},
       additional_info: '{"note": "x"}'}
    end

    it "lists the kinds as an expandable table with links to their pages" do
      get "/document_management/document_kinds"

      expect(response).to have_http_status(200)
      row = html.find("tr.exp-row", text: "Medizinbogen")
      expect(row).to have_text("alle Rollen Pflicht · angeboten für update · nicht in registered")
      expect(row).to have_css(".dk-rights-line", text: "lesen person update")
      expect(row).to have_css(".dk-rights-line", text: "schreiben · löschen log")
      expect(row).to have_css(".dk-files.wsjrdp-html-tip[data-bs-title*='application/pdf']")
      expect(html).to have_css("th", text: "Dok.")

      good_conduct = html.find("tr.exp-row", text: "Nachweis über ein Führungszeugnis")
      expect(good_conduct).to have_css(".dk-rule", count: 2)
      expect(good_conduct).to have_text("eFZ-Einsicht-fehlt ab in_review … confirmed")
      expect(row).to have_link(href: "/document_management/document_kinds/#{medical.id}", count: 2)
      expect(row).to have_css("td[data-colkey=_page] .exp-page-link a[target=_blank][href='/document_management/document_kinds/#{medical.id}']")
      # Where the page column gives way, the detail's link: floated, no line of its own.
      expect(html).to have_css(".exp-detail-linkbar.exp-detail-linkbar-float[data-exp-if-any-hidden]", visible: :all)
      expect(html).to have_css("turbo-frame[src^='/document_management/document_kinds/#{medical.id}']", visible: :all)
      # On a phone the kind's page is the detail's double button.
      expect(html).to have_css(".exp-detail-linkbar a[href='/document_management/document_kinds/#{medical.id}']",
        visible: :all)
    end

    it "shows label and keys in one cell, each with a sortable header, the subject type on demand" do
      get "/document_management/document_kinds"
      row = html.find("tr.exp-row", text: "Medizinbogen")
      expect(row).to have_css("td.exp-merged", text: /\AMedizinbogen\s*medical\z/)
      expect(row).to have_no_text("Person")
      expect(html).to have_css("th", text: "Bezeichnung").and have_css("th", text: "Schlüs\u00ADsel")
      # The label always on a row of its own over the keys.
      expect(html).to have_no_css("thead tr:has(th[data-colkey=label]) th[data-colkey=key]")

      get "/document_management/document_kinds", params: {c: "lb,st"}
      row = html.find("tr.exp-row", text: "Medizinbogen")
      expect(row).to have_no_text("medical").and have_css("td", text: "Person")
    end

    it "sorts by the keys" do
      get "/document_management/document_kinds", params: {s: "k"}

      labels = html.all("tr.exp-row td:first-child > div:first-child").map(&:text)
      expect(labels.first).to eq("Vertrag (Anmeldung)")
      expect(labels.last).to eq("SEPA-Mandat")
    end

    it "shows a kind as its form, on its page and in its row" do
      get "/document_management/document_kinds/#{medical.id}"
      expect(html).to have_css("h1", text: "Medizinbogen")
      expect(html).to have_css("h1 .kind-eyebrow", text: "Dokument-Art")
      expect(html).to have_css(".nav .active", text: "Arten")
      expect(html).to have_select("kind[readable_by][]", selected: %w[person update], visible: :all)
      expect(html).to have_select("kind[content_types][]", selected: %w[application/pdf], visible: :all)
      expect(html).to have_select("kind[extensions][]", selected: %w[pdf], visible: :all)
      types = JSON.parse(html.find("script#wsjrdp-tag-source-content-types", visible: :all).text(:all))
      expect(types).to include(["application/pdf", ".pdf"], ["image/*", "alle Typen dieser Familie"])
      extensions = JSON.parse(html.find("script#wsjrdp-tag-source-extensions", visible: :all).text(:all))
      expect(extensions).to include(["eml", "message/rfc822"])
      words = html.find("[data-kind-file-kind]", text: "Textverarbeitung")
      expect(words).to have_css("button[data-kind-file-kind-action=toggle]", text: "Textverarbeitung")
      expect(words).to have_button("Textverarbeitung ganz abwählen", visible: :all)
      expect(JSON.parse(words["data-kind-file-kind"])).to include("extensions" => %w[doc docx dot dotx odt ott])
      expect(JSON.parse(words["data-kind-file-kind"])["types"]).to include("application/msword",
        "application/vnd.oasis.opendocument.text-template")
      expect(JSON.parse(words["data-kind-file-kind"])["groups"].first).to include("type" => "application/msword",
        "extensions" => %w[doc dot])
      expect(html).to have_css("[data-kind-accepted]", visible: :all)
      expect(html).to have_css(".kind-rule", count: 1)
      expect(html).to have_css(".kind-key-count", text: "7/40")
      expect(html).to have_css(".kind-key-count[hidden]", visible: :all)
      messages = JSON.parse(html.find("[data-kind-key]", match: :first)["data-messages"])
      expect(messages).to include("too_long" => "Höchstens 40 Zeichen.")
      expect(html).to have_css("template[data-kind-rule-template]", visible: :all)
      expect(html).to have_css("input[name$='[missing_tag]'][list='kind-#{medical.id}-person-tags']", visible: :all)
      expect(html).to have_css("datalist#kind-#{medical.id}-person-tags", visible: :all)

      get "/document_management/document_kinds/#{medical.id}", headers: {"Turbo-Frame" => "bkframe-dk-#{medical.id}"},
        env: {"HTTP_REFERER" => "http://www.example.com/document_management/document_kinds?s=lb"}
      expect(html).to have_no_css("h1")
      expect(html).to have_field("return_to", type: :hidden, with: "/document_management/document_kinds?s=lb")
    end

    it "keeps the section's tabs on the form of a new kind" do
      get "/document_management/document_kinds/new"
      expect(html).to have_css(".nav-sub .active", text: "Arten")
    end

    it "creates a kind with its rules in the order of their cards, and keeps additional_info" do
      post "/document_management/document_kinds", params: {kind: form}

      kind = WsjrdpDocumentKind.find_by!(key: "brief")
      expect(response).to redirect_to("/document_management/document_kinds/#{kind.id}")
      expect(kind).to have_attributes(label: "Brief", readable_by: %w[person log], writable_by: %w[log],
        content_types: %w[application/pdf image/*], extensions: nil, max_upload_size_mb: 5, additional_info: {})
      expect(kind.role_rules).to eq([
        {"roles" => %w[UL], "offer_to" => %w[update], "required" => true},
        {"offer_to" => %w[log], "not_for_status" => %w[registered],
         "missing_tag" => {"tag" => "Brief-fehlt", "from_status" => %w[reviewed], "remove_on_upload" => true}}
      ])
    end

    it "shows the form again with what is wrong" do
      post "/document_management/document_kinds", params: {kind: form.merge(key: "Letter", readable_by: ["Log!"])}

      expect(response).to have_http_status(422)
      expect(html).to have_css(".document-kind-errors", text: "Log!")
    end

    it "saves back to the list it was opened in, and fixes the keys once documents have them" do
      patch "/document_management/document_kinds/#{medical.id}",
        params: {return_to: "/document_management/document_kinds?s=lb", kind: form.merge(label: "Medizin", key: "medicine").except(:rules)}
      expect(response).to redirect_to("/document_management/document_kinds?s=lb")
      expect(medical.reload).to have_attributes(label: "Medizin", key: "medicine", role_rules: [])

      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"), {subject: person, key: "medicine", filename: "a.pdf"})
      patch "/document_management/document_kinds/#{medical.id}",
        params: {return_to: "https://elsewhere.example/x", kind: form.merge(key: "other")}
      expect(response).to redirect_to("/document_management/document_kinds/#{medical.id}")
      expect(medical.reload.key).to eq("medicine")
      get "/document_management/document_kinds/#{medical.id}"
      expect(html).to have_field("kind[key]", with: "medicine", disabled: true)
      expect(html).to have_no_button("Dokument-Art löschen")
    end

    it "offers to delete a kind without documents beside Save" do
      get "/document_management/document_kinds/#{medical.id}"

      button = html.find("button", text: "Dokument-Art löschen")
      expect(button[:form]).to eq("kind-#{medical.id}-destroy")
      expect(html).to have_css("form#kind-#{medical.id}-destroy[action='/document_management/document_kinds/#{medical.id}']" \
        " input[name=_method][value=delete]", visible: :all)
    end

    it "deletes only a kind without documents" do
      Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4"), {subject: person, key: "medical", filename: "a.pdf"})

      expect { delete "/document_management/document_kinds/#{medical.id}" }.not_to change(WsjrdpDocumentKind, :count)
      expect(flash[:alert]).to be_present

      sepa = wsjrdp_document_kinds(:sepa)
      expect { delete "/document_management/document_kinds/#{sepa.id}" }.to change(WsjrdpDocumentKind, :count).by(-1)
    end
  end
end
