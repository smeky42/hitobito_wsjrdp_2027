# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

  namespace :public do
    get "statistics", to: "statistics#index"
  end

  # The session UI's background target (doc/roles.md -> "The finance cap").
  post "session_settings", to: "session_settings#update", as: :session_settings
  # The admin tab's person search: look somebody up
  # (Wsjrdp::ImpersonationQueryController), then impersonate them, or switch
  # out of a running impersonation (Wsjrdp::ImpersonationController). Both act
  # for the person who actually logged in, not for the impersonated one.
  get "wsjrdp/impersonate/people", to: "wsjrdp/impersonation_query#index",
    as: :wsjrdp_impersonate_query
  post "wsjrdp/impersonate", to: "wsjrdp/impersonation#create", as: :wsjrdp_impersonate
  # The person search of a service token's acting person, for admins
  # (Wsjrdp::ServiceTokenActingPeopleController).
  get "wsjrdp/service_tokens/acting_people", to: "wsjrdp/service_token_acting_people#index",
    as: :wsjrdp_service_token_acting_people

  # The stored documents, whatever their subject (Wsjrdp::DocumentsController,
  # doc/wsjrdp/documents.md); read through the API as "documents"
  # (JsonApi::DocumentsController).
  scope path: ApplicationResource.endpoint_namespace, module: :json_api,
    constraints: {format: "jsonapi"}, defaults: {format: "jsonapi"} do
    resources :documents, only: [:index, :show], as: :json_api_documents
  end

  language_scope do
    # Einstellungen > Ländercodes (CountryCodesController).
    get "country_codes" => "country_codes#index", :as => :country_codes
    post "country_codes/migrate" => "country_codes#migrate", :as => :migrate_country_codes
    # For admins: the main section Dokumente (every document, also grouped by
    # kind, and the kinds of document) and the Dokumentenverwaltung in
    # Einstellungen (the overview, registering the registration uploads).
    get "document_management" => "document_management#index", :as => :document_management
    # Checking the files of all documents (Wsjrdp2027::CheckDocumentFilesJob).
    scope "document_management/check_files", controller: "document_management" do
      post "/" => :check_files, :as => :document_management_check_files
      get "progress" => :check_files_progress, :as => :document_management_check_files_progress
      post "cancel" => :check_files_cancel, :as => :document_management_cancel_check_files
    end
    get "documents" => "document_management/documents#index", :as => :document_management_documents
    post "documents/apply" => "document_management/documents#apply", :as => :document_management_apply_documents
    get "documents/:id/details" => "document_management/documents#show", :as => :document_management_document
    get "documents/by_person_and_kind" => "document_management/document_groups#index", :as => :document_management_document_groups
    post "documents/by_person_and_kind/apply" => "document_management/document_groups#apply",
      :as => :document_management_apply_document_groups
    # One group, by DocumentManagement::DocumentGroups::Group#to_param.
    get "documents/by_person_and_kind/:id" => "document_management/document_groups#show",
      :as => :document_management_document_group
    scope "document_management/registration_documents", controller: "document_management/registration_documents" do
      get "/" => :index, :as => :document_management_registration_documents
      post "apply" => :apply, :as => :document_management_apply_registration_documents
      get "progress" => :progress, :as => :document_management_registration_documents_progress
      post "cancel" => :cancel, :as => :document_management_cancel_registration_documents
      post "register" => :register, :as => :document_management_register_documents
      post "register_all" => :register_all, :as => :document_management_register_all_documents
    end
    scope "document_management", module: "document_management", as: "document_management" do
      resources :document_kinds, except: [:edit]
    end

    resources :documents, only: [:show, :create], controller: "wsjrdp/documents", as: :wsjrdp_documents

    # The status, medical and Zusatzdaten pages without a group: in the
    # person's primary group (Person::StatusController#group).
    get "people/:id/status" => "person/status#show", :as => :status_person
    get "people/:id/status/edit" => "person/status#edit", :as => :status_edit_person
    put "people/:id/status" => "person/status#update"
    get "people/:id/medical" => "person/medical#show", :as => :medical_person
    get "people/:id/medical/edit" => "person/medical#edit", :as => :medical_edit_person
    put "people/:id/medical" => "person/medical#update"
    get "people/:id/jamboree_data" => "person/jamboree_data#show", :as => :jamboree_data_person
    get "people/:id/jamboree_data/edit" => "person/jamboree_data#edit", :as => :jamboree_data_edit_person
    put "people/:id/jamboree_data" => "person/jamboree_data#update"
    post "people/:id/status/review_documents" => "person/status#review_documents"
    post "people/:id/status/approve_documents" => "person/status#approve_documents"
    get "people/:id/status/primary_role" => "person/primary_role#show", :as => :status_primary_role_person
    post "people/:id/status/primary_role" => "person/primary_role#create"
    # The documents the status page links to.
    %w[contract sepa medical data_agreement passport recommendation photo_permission good_conduct].each do |doc|
      get "people/:id/upload/show_#{doc}" => "person/upload#show_#{doc}"
    end
    # The person's page itself, /people/:id, is a route of its own
    # (lib/hitobito_wsjrdp_2027/wagon.rb, wsjrdp_2027.person_page_route).
    # The print, upload, unit, history, log and security pages without a
    # group, in the person's primary group too (Wsjrdp2027::PeopleHelper,
    # person_subpage_path); the security page's actions stay in the group's
    # URL and come back to the short one.
    get "people/:id/print" => "person/print#index", :as => :print_person
    put "people/:id/print" => "person/print#index"
    get "people/:id/print/preview" => "person/print#preview"
    get "people/:id/print/submit" => "person/print#submit"
    get "people/:id/upload" => "person/upload#index", :as => :upload_person
    put "people/:id/upload" => "person/upload#index"
    get "people/:id/upload/show_registration_generated" => "person/upload#show_registration_generated"
    delete "people/:id/upload/delete/:what" => "person/upload#destroy"
    get "people/:id/unit" => "person/unit#show", :as => :unit_person
    post "people/:id/unit/fill_cluster_code" => "person/unit#fill_cluster_code"
    post "people/:id/unit/clear_cluster_code" => "person/unit#clear_cluster_code"
    get "people/:id/history" => "person/history#index", :as => :history_person
    get "people/:id/log" => "person/log#index", :as => :log_person
    get "people/:id/security_tools" => "person/security_tools#index", :as => :security_tools_person

    resources :groups do
      # An API key's token is shown only as it is made
      # (Wsjrdp2027::ServiceTokensController), so a lost token is replaced.
      resources :service_tokens, only: [] do
        member do
          post :regenerate_token
        end
      end

      resources :people, except: [:new, :create] do
        member do
          post :send_password_instructions
          put :primary_group

          get "print" => "person/print#index"
          put "print" => "person/print#index"
          get "print/preview" => "person/print#preview"
          get "print/submit" => "person/print#submit"

          get "accounting" => "person/fee#show"
          # The finance pages in the group of the URL too, beside
          # /people/:person_id/... (PersonInPrimaryGroup#group).
          get "fee" => "person/fee#show"
          get "finance" => "person/fee#show"
          get "spend" => "person/spend#show"
          get "deregistration" => "person/deregistration#show"

          get "upload" => "person/upload#index"
          put "upload" => "person/upload#index"
          get "upload/show_registration_generated" => "person/upload#show_registration_generated"
          get "upload/show_contract" => "person/upload#show_contract"
          get "upload/show_sepa" => "person/upload#show_sepa"
          get "upload/show_medical" => "person/upload#show_medical"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_passport" => "person/upload#show_passport"
          get "upload/show_recommendation" => "person/upload#show_recommendation"
          get "upload/show_photo_permission" => "person/upload#show_photo_permission"
          get "upload/show_good_conduct" => "person/upload#show_good_conduct"
          delete "upload/delete/:what" => "person/upload#destroy"

          get "medical" => "person/medical#show"
          get "medical/edit" => "person/medical#edit"
          put "medical" => "person/medical#update"

          get "jamboree_data" => "person/jamboree_data#show"
          get "jamboree_data/edit" => "person/jamboree_data#edit"
          put "jamboree_data" => "person/jamboree_data#update"

          get "status" => "person/status#show"
          get "status/primary_role" => "person/primary_role#show"
          post "status/primary_role" => "person/primary_role#create"
          get "status/edit" => "person/status#edit"
          put "status" => "person/status#update"
          post "status/review_documents" => "person/status#review_documents"
          post "status/approve_documents" => "person/status#approve_documents"

          get "unit" => "person/unit#show"
          post "unit/fill_cluster_code" => "person/unit#fill_cluster_code"
          post "unit/clear_cluster_code" => "person/unit#clear_cluster_code"
        end
      end

      get "map" => "group/map#index"
      get "patrols" => "group/patrols#index", :as => :patrols
      put "patrols" => "group/patrols#update"
      # The Buchhaltung sub-tab of the group's Finanzen tab. The action is
      # :show, not :index, so the leaf sheet keeps its sub-tabs
      # (doc/navigation.md).
      get "finance/bookkeeping" => "group/bookkeeping#show", :as => :finance_bookkeeping
      # PRG target of the bookings table's filter builder (see
      # Wsjrdp::TableStateful#wsjrdp_apply_table_filter).
      post "finance/bookkeeping/apply" => "group/bookkeeping#apply",
        :as => :finance_bookkeeping_apply
      # ONE booking of the group: the page a row of that table links to and the
      # pane it lazy-loads. The id is looked up within the group's cost centers
      # only (Group::BookingsController), so this route opens nothing the
      # Buchhaltung tab does not already list.
      get "finance/bookkeeping/bookings/:id" => "group/bookings#show",
        :as => :finance_bookkeeping_booking
      # Editing has a page of its own, reached from the reading page above and
      # gated on :update_finance; the pane inside the table keeps its inline
      # toggle and posts to #update directly.
      get "finance/bookkeeping/bookings/:id/edit" => "group/bookings#edit",
        :as => :edit_finance_bookkeeping_booking
      patch "finance/bookkeeping/bookings/:id" => "group/bookings#update"
    end

    get "groups/:group_id/statistics/data", to: "group/statistics#statistics_data", defaults: {format: :json}

    concern :tx_actions do |options|
      controller = options[:controller]
      post "create_accounting_entry", to: "#{controller}#create_accounting_entry"
      post "link_accounting_entry/:accounting_entry_id", to: "#{controller}#link_accounting_entry"
      post "link_subject/:subject_id/:subject_type", to: "#{controller}#link_subject"
      post "disallow_link_subject/:subject_id/:subject_type", to: "#{controller}#disallow_link_subject"
    end

    resources :people, only: [] do
      resource :finance, controller: "person/fee", only: [:show]
      resource :accounting, controller: "person/fee", only: [:show]
      resource :fee, controller: "person/fee", only: [:show] do
        # The page's entries on paper, compiled on the fly
        member do
          get :statement
        end
      end
      resource :spend, controller: "person/spend", only: [:show]
      get :moss_sso_login, path: "person/spend/moss_sso_login", to: "person/spend#moss_sso_login"
      resource :deregistration, controller: "person/deregistration", only: [:show, :edit, :update] do
        # The two documents of the page, rendered on the fly and stored nowhere:
        # the declaration the person signs and the receipt the finance team pays
        # the refund from -- both GETs, since what they carry is edited on the
        # form. Each answers the PDF inline, the same PDF as a file to save
        # behind download=1, and page 1 as a picture under .png. :sections is
        # what the page writes back when one of its collapsibles opens or closes.
        member do
          get :form
          post :create_form
          post :discard_form
          get :refund_receipt
          post :create_receipt
          post :discard_receipt
          post :sections
        end
      end
      resource :debit_return, controller: "person/debit_return", only: [:edit, :update]
      # The fee reduction section of the person finance page: plan, activate or discard
      # a total fee reduction.
      resource :fee_reduction, controller: "person/fee_reduction", only: [:edit, :update] do
        get :buttons
        post :activate
        post :discard
      end
      # The installment plan section of the person finance page: plan, activate or
      # discard an individual installment plan.
      resource :installments, controller: "person/installments", only: [:edit, :update] do
        get :buttons
        post :activate
        post :discard
      end
    end

    scope "fin", module: "fin" do
      get :person_fees, as: "fin_person_fees", to: "wsjrdp_fin_person_fees#index"
      # The people with an active total fee reduction (Reduktionen tab of the
      # Beiträge area).
      get :individual_payment_plans, as: "fin_individual_payment_plans", to: "individual_payment_plans#index"
      post "individual_payment_plans/apply", as: "apply_fin_individual_payment_plans",
        to: "individual_payment_plans#apply"
      get :fee_reductions, as: "fin_fee_reductions", to: "fee_reductions#index"
      post "fee_reductions/apply", as: "apply_fin_fee_reductions", to: "fee_reductions#apply"
      get :new_sepa_status, path: "ae/new_sepa_status", to: "accounting_entries#new_sepa_status"
      post :new_sepa_status, path: "ae/new_sepa_status", to: "accounting_entries#new_sepa_status"
      resources :accounting_entries, path: "ae", only: [:new, :create, :index, :show, :edit, :update, :destroy]
      resources :moss_bookings, controller: "moss_bookings", path: "moss_booking", only: [:show, :update] do
        concerns :tx_actions, controller: "moss_bookings"
        # Link a person AND create their Beitragsbuchung in one step (Moss only,
        # hence not in :tx_actions, which the camt transactions share).
        post "link_subject_and_create_accounting_entry/:subject_id/:subject_type",
          to: "moss_bookings#link_subject_and_create_accounting_entry"
      end
      resources :wsjrdp_camt_transactions, path: "tx", only: [:show, :update] do
        concerns :tx_actions, controller: "wsjrdp_camt_transactions"
      end
      resources :wsjrdp_fin_accounts, path: "acc", only: [:index, :show, :update] do
        member do
          # PRG target of the CNF filter builder on the Moss wallet's statement
          # (Fin::WsjrdpFinAccountsController#apply) -- a member route because
          # the filter belongs to ONE account's table.
          post :apply
        end
      end
      resources :wsjrdp_direct_debit_pre_notifications, path: "pn", only: [:show, :edit, :update]
      resources :wsjrdp_payment_plans, path: "payment_plans", only: [:index, :show, :update]
      # "Moss" section: overview at /fin/moss (own controller) + the transactions
      # list at /fin/moss/transactions (own controller). See doc/navigation.md.
      get :moss, path: "moss", to: "moss#index", as: "moss"
      resources :moss_transactions, path: "moss/transactions", only: [:index, :show] do
        collection do
          post :apply # PRG target of the CNF filter builder
        end
      end
      # The four kind tabs (Kartenzahlungen, Rechnungen, Erstattungen,
      # Einzahlungen): the same transactions list pinned to one kind. The kind
      # travels as a route default, the way hitobito's Anlässe / Kurse tabs
      # share events#index -- so every tab has a path helper of its own
      # (moss_invoices_path, apply_moss_invoices_path, ...) for Sheet::Fin::Moss.
      # Fin::MossTransactionsController::KIND_TABS mirrors this map.
      {card_transactions: "MossCardTransaction", reimbursements: "MossReimbursement",
       invoices: "MossInvoice", top_ups: "MossTopUp"}.each do |slug, kind|
        get "moss/#{slug}", to: "moss_transactions#index", kind: kind, as: "moss_#{slug}"
        post "moss/#{slug}/apply", to: "moss_transactions#apply", kind: kind, as: "apply_moss_#{slug}"
      end
      # "Zahlungsverkehr" section: its overview at /fin/payments, the orders
      # (SEPA files), the debits and the returns. See doc/fin/payments.md.
      get :payments, path: "payments", to: "payments#index", as: "fin_payments"
      resources :payment_orders, path: "payments/orders", only: [:index, :show] do
        collection { post :apply }
        member { post :apply_debits }
      end
      resources :direct_debit_payment_infos, only: [:index, :show] do
        collection { post :apply }
        member { post :apply_debits }
      end
      resources :direct_debits, path: "payments/debits", only: [:index, :show, :edit, :update] do
        collection { post :apply }
      end
      resources :payment_returns, path: "payments/returns", only: [:index, :show] do
        collection { post :apply }
      end
      # "Beiträge" section: its overview page at /fin/fees; the two lists it
      # links to (person_fees, payment_plans) have their own routes above.
      # See doc/navigation.md.
      get :fees, path: "fees", to: "fees#index", as: "fees"
      # "Controlling" section: its overview page at /fin/controlling and the
      # Budget page. See doc/navigation.md.
      get :controlling, path: "controlling", to: "controlling#index", as: "controlling"
      # Budget and DATEV actuals per cost center and year.
      get "controlling/budget", to: "budgets#index", as: "controlling_budget"
      # "Verwaltung" section at /fin/admin: the configuration pages of the
      # Finanzen section, all gated on :configure_finance on Group. The area
      # has no page of its own -- /fin/admin renders its first tab, the
      # payment codes.
      get :admin, path: "admin", to: "payment_references#index", as: "fin_admin"
      scope "admin" do
        # Per-group finance access (people.additional_info["finance_group_ids"]).
        # The page is a two-stage editor over all rows, so the write is a
        # COLLECTION route: one PATCH carries the whole change list.
        get "finance_groups", to: "finance_groups#index", as: "fin_admin_finance_groups"
        # Named explicitly: without an `as:` Rails would derive the helper from
        # the path segment alone (finance_groups_path) and hide the area.
        patch "finance_groups", to: "finance_groups#apply",
          as: "fin_admin_apply_finance_groups"
        # The cost centers of a group (groups.additional_info["cost_center_numbers"]).
        # The page is ONE form carrying every group's list, so the write is a
        # COLLECTION route; the form posts to fin_admin_group_cost_centers_path.
        get "group_cost_centers", to: "group_cost_centers#index", as: "fin_admin_group_cost_centers"
        patch "group_cost_centers", to: "group_cost_centers#update",
          as: "fin_admin_save_group_cost_centers"
        # The payment references (payment codes) and the stock of available
        # ones; the POST makes new ones for the stock, /apply is the PRG target
        # of the list's filter builder, /:id a code's page (and the lazy detail
        # of its row).
        get "payment_references", to: "payment_references#index", as: "fin_admin_payment_references"
        post "payment_references", to: "payment_references#generate",
          as: "fin_admin_generate_payment_references"
        post "payment_references/apply", to: "payment_references#apply",
          as: "fin_admin_apply_payment_references"
        get "payment_references/:id", to: "payment_references#show", as: "fin_admin_payment_reference",
          constraints: {id: /\d+/}
        # Only the comment of a code is editable, inline on its page and in
        # its row's detail.
        patch "payment_references/:id", to: "payment_references#update", constraints: {id: /\d+/}
      end
      # /fin is the finance overview page, linking to the sections.
      get :fin, path: "", to: "overview#index"

      # Buchhaltung (accounting) at /fin/bookkeeping: one resource controller
      # per master-data entity plus the section overview.
      get "bookkeeping", to: "bookkeeping#overview", as: "bookkeeping"
      scope "bookkeeping" do
        # Ledger accounts (Sachkonten) and personal accounts (Kreditoren /
        # Debitoren) are keyed by their numeric DATEV account number.
        # :show is the reading page, :edit the form page it leads to and
        # :update its target -- the same view/edit split the bookings use, for
        # the one field an account carries that Hitobito owns (is_unit_budget).
        resources :ledger_accounts, param: :number, only: [:index, :show, :edit, :update],
          constraints: {number: /\d+/} do
          collection do
            # Apply target of the generic CNF filter builder (PRG; see
            # Fin::LedgerAccountsController#apply).
            post :apply
          end
        end
        # Cost-center numbers may contain LETTERS -- deliberately unconstrained.
        resources :cost_centers, param: :number, only: [:index, :show, :edit, :update] do
          collection do
            # Apply target of the generic CNF filter builder (PRG; see
            # Fin::CostCentersController#apply).
            post :apply
          end
        end
        resources :personal_accounts, param: :number, only: [:index, :show, :edit, :update],
          constraints: {number: /\d+/} do
          collection do
            # Apply target of the generic CNF filter builder (PRG; see
            # Fin::PersonalAccountsController#apply).
            post :apply
          end
        end
        # Buchungsstapel (DATEV booking batch / Primanota) list and detail pages.
        resources :booking_batches, only: [:index, :show] do
          collection do
            post :apply
          end
        end
        # :update is the ONE endpoint for all manual associations of the booking
        # detail view (person assign/clear, entry connect/unlink): each mini-form
        # PATCHes a field subset of datev_booking (see BookingsController#update).
        # :show is the reading page, :edit the form page it leads to.
        resources :bookings, only: [:index, :show, :edit, :update] do
          collection do
            # Apply target of the generic CNF filter builder (PRG; see
            # Fin::BookingsController#apply).
            post :apply
          end
          member do
            # JSON source for the entry autocomplete (same-amount unlinked
            # entries) in the booking detail view.
            get :query_entries
          end
        end
      end

      # Abstimmung (reconciliation) -- matching accounting entries with DATEV
      # bookings. Finanzen nav item next to Beiträge / Buchhaltung.
      get "reconciliation", to: "reconciliation#overview", as: "reconciliation"
      get "reconciliation/participant_fees", to: "reconciliation#participant_fees",
        as: "reconciliation_participant_fees"
      post "reconciliation/participant_fees/apply", to: "reconciliation#apply_participant_fees",
        as: "apply_reconciliation_participant_fees"
      post "reconciliation/participant_fees/connect", to: "reconciliation#connect_participant_fees",
        as: "connect_reconciliation_participant_fees"
      post "reconciliation/participant_fees/connect_single", to: "reconciliation#connect_single",
        as: "connect_single_reconciliation_participant_fees"
      post "reconciliation/participant_fees/connect_entries", to: "reconciliation#connect_participant_entries",
        as: "connect_entries_reconciliation_participant_fees"
      post "reconciliation/participant_fees/connect_single_entry", to: "reconciliation#connect_single_entry",
        as: "connect_single_entry_reconciliation_participant_fees"
      # Unit-Buchungen: the bookings the units see, starting with the ones that
      # neither count against a Unit-Budget nor name a secondary cost center
      # (Fin::UnitBookingsController).
      get "reconciliation/unit_bookings", to: "unit_bookings#index", as: "reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/apply", to: "unit_bookings#apply",
        as: "apply_reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/bulk", to: "unit_bookings#bulk",
        as: "bulk_reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/bulk/preview", to: "unit_bookings#bulk_preview",
        as: "bulk_preview_reconciliation_unit_bookings"
      # DEVELOPMENT ONLY: reset every DATEV booking's links, to replay the
      # reconciliation while testing. The route does not exist in production.
      if Rails.env.development?
        post "reconciliation/participant_fees/reset_links", to: "reconciliation#reset_links",
          as: "reset_links_reconciliation_participant_fees"
      end
    end

    namespace "contingent" do
      get :contingent, path: "", to: "wsjrdp_contingent#index"
      post :show_people_links, to: "wsjrdp_contingent#show_people_links"
      post :hide_people_links, to: "wsjrdp_contingent#hide_people_links"
      get :cmt, to: "wsjrdp_cmt#index"
      get :ist, to: "wsjrdp_ist#index"
    end
  end
end
