# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

  namespace :public do
    get "statistics", to: "statistics#index"
  end

  post "session_settings", to: "session_settings#update", as: :session_settings
  # Both act for the person who logged in, not the impersonated one.
  get "wsjrdp/impersonate/people", to: "wsjrdp/impersonation_query#index",
    as: :wsjrdp_impersonate_query
  post "wsjrdp/impersonate", to: "wsjrdp/impersonation#create", as: :wsjrdp_impersonate
  # Admins only.
  get "wsjrdp/service_tokens/acting_people", to: "wsjrdp/service_token_acting_people#index",
    as: :wsjrdp_service_token_acting_people

  scope path: ApplicationResource.endpoint_namespace, module: :json_api,
    constraints: {format: "jsonapi"}, defaults: {format: "jsonapi"} do
    resources :documents, only: [:index, :show], as: :json_api_documents
  end

  language_scope do
    get "country_codes" => "country_codes#index", :as => :country_codes
    post "country_codes/migrate" => "country_codes#migrate", :as => :migrate_country_codes
    get "document_management" => "document_management#index", :as => :document_management
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
    get "documents/by_person_and_kind/:id" => "document_management/document_groups#show",
      :as => :document_management_document_group
    scope "document_management/registration_documents", controller: "document_management/registration_documents" do
      get "/" => :index, :as => :document_management_registration_documents
      post "apply" => :apply, :as => :document_management_apply_registration_documents
      get "progress" => :progress, :as => :document_management_registration_documents_progress
      post "cancel" => :cancel, :as => :document_management_cancel_registration_documents
      post "register" => :register, :as => :document_management_register_documents
      post "register_all" => :register_all, :as => :document_management_register_all_documents
      get "unregistered_file" => :unregistered_file, :as => :document_management_unregistered_registration_file
      post "adopt_file" => :adopt_file, :as => :document_management_adopt_registration_file
      post "set_aside_file" => :set_aside_file, :as => :document_management_set_aside_registration_file
    end
    scope "document_management", module: "document_management", as: "document_management" do
      resources :document_kinds, except: [:edit]
    end

    resources :documents, only: [:show, :create], controller: "wsjrdp/documents", as: :wsjrdp_documents

    scope "credentials/versions/:id", controller: "credential_versions", constraints: {id: /\d+/} do
      get "edit" => :edit, :as => :edit_credential_version
      patch "/" => :update, :as => :credential_version
      delete "/" => :destroy
      post "revoke" => :revoke, :as => :revoke_credential_version
      post "unrevoke" => :unrevoke, :as => :unrevoke_credential_version
      post "rekey" => :rekey, :as => :rekey_credential_version
    end
    get "credentials" => "credentials#index", :as => :credentials
    get "credentials/new" => "credentials#new", :as => :new_credential
    post "credentials/reload_local_file" => "credentials#reload_local_file", :as => :reload_local_file_credentials
    scope "credentials/:kind/:account_key", constraints: {kind: %r{[^/]+}, account_key: %r{[^/]+}}, format: false do
      get "/" => "credentials#show", :as => :credential
      post "reveal" => "credentials#reveal", :as => :reveal_credential
      post "connection_test" => "credentials#test_connection", :as => :test_connection_credential
      get "versions/new" => "credential_versions#new", :as => :new_credential_version
      post "versions" => "credential_versions#create", :as => :credential_versions
    end

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
    %w[contract sepa medical data_agreement passport recommendation photo_permission good_conduct].each do |doc|
      get "people/:id/upload/show_#{doc}" => "person/upload#show_#{doc}"
    end
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
      # A token is shown only once, at creation.
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
      # :show, not :index, so the leaf sheet keeps its sub-tabs.
      get "finance/bookkeeping" => "group/bookkeeping#show", :as => :finance_bookkeeping
      post "finance/bookkeeping/apply" => "group/bookkeeping#apply",
        :as => :finance_bookkeeping_apply
      # The id is looked up within the group's cost centers only.
      get "finance/bookkeeping/bookings/:id" => "group/bookings#show",
        :as => :finance_bookkeeping_booking
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
        member do
          get :statement
        end
      end
      resource :spend, controller: "person/spend", only: [:show]
      get :moss_sso_login, path: "person/spend/moss_sso_login", to: "person/spend#moss_sso_login"
      resource :deregistration, controller: "person/deregistration", only: [:show, :edit, :update] do
        member do
          get :form
          post :create_form
          post :prepare_form # API key
          post :discard_form
          post :new_version
          post :form_sent # API key only
          post :confirmation_sent # API key only
          get :mail_file
          get :refund_receipt
          post :create_receipt
          post :discard_receipt
          post :sections
        end
      end
      resource :debit_return, controller: "person/debit_return", only: [:edit, :update]
      resource :family_members, controller: "person/family_members", only: [:edit, :update]
      resource :fee_reduction, controller: "person/fee_reduction", only: [:edit, :update] do
        get :buttons
        post :activate
        post :discard
      end
      resource :bank_account, controller: "person/bank_account", only: [:edit, :update] do
        get :buttons
        get :mandate
      end
      resource :installments, controller: "person/installments", only: [:edit, :update] do
        get :buttons
        get :preview
        post :activate
        post :discard
      end
    end

    scope "fin", module: "fin" do
      get :person_fees, as: "fin_person_fees", to: "wsjrdp_fin_person_fees#index"
      get :individual_payment_plans, as: "fin_individual_payment_plans", to: "individual_payment_plans#index"
      post "individual_payment_plans/apply", as: "apply_fin_individual_payment_plans",
        to: "individual_payment_plans#apply"
      get :fee_reductions, as: "fin_fee_reductions", to: "fee_reductions#index"
      post "fee_reductions/apply", as: "apply_fin_fee_reductions", to: "fee_reductions#apply"
      get :new_sepa_status, path: "ae/new_sepa_status", to: "accounting_entries#new_sepa_status"
      post :new_sepa_status, path: "ae/new_sepa_status", to: "accounting_entries#new_sepa_status"
      resources :accounting_entries, path: "ae", only: [:new, :create, :index, :show, :edit, :update, :destroy]
      # Old address, still linked from outside.
      get "moss_booking/:id", to: redirect("/fin/moss/bookings/%{id}"), constraints: {id: /\d+/}
      resources :wsjrdp_camt_transactions, path: "tx", only: [:show, :edit, :update] do
        concerns :tx_actions, controller: "wsjrdp_camt_transactions"
      end
      # acc/all and acc/internal_transfers come before the accounts, so neither is read as an id.
      get "acc/all", to: "account_transactions#index", as: "fin_account_transactions"
      post "acc/all/apply", to: "account_transactions#apply", as: "apply_fin_account_transactions"
      get :transaction_picker, path: "transaction_picker", to: "transaction_picker#index"
      resources :internal_transfers, path: "acc/internal_transfers" do
        collection do
          post :link
          post :dismiss
          post :link_unique # service token
          post :apply
        end
      end
      resources :wsjrdp_fin_accounts, path: "acc", only: [:index, :show, :edit, :update] do
        member do
          post :apply
        end
      end
      resources :wsjrdp_direct_debit_pre_notifications, path: "pn", only: [:show, :edit, :update]
      resources :wsjrdp_payment_plans, path: "payment_plans", only: [:index, :show, :update] do
        member { get :preview }
      end
      get :moss, path: "moss", to: "moss#index", as: "moss"
      resources :moss_transactions, path: "moss/transactions", only: [:index, :show, :edit, :update] do
        collection do
          post :apply
        end
      end
      # The kind travels as a route default, so every tab gets its own path helper.
      {card_transactions: "MossCardTransaction", reimbursements: "MossReimbursement",
       invoices: "MossInvoice", top_ups: "MossTopUp"}.each do |slug, kind|
        get "moss/#{slug}", to: "moss_transactions#index", kind: kind, as: "moss_#{slug}"
        post "moss/#{slug}/apply", to: "moss_transactions#apply", kind: kind, as: "apply_moss_#{slug}"
      end
      resources :moss_expenses, path: "moss/expenses", only: [:show, :edit, :update]
      resources :moss_bookings, path: "moss/bookings", only: [:index, :show, :edit, :update] do
        collection do
          post :apply
        end
        concerns :tx_actions, controller: "moss_bookings"
        # Moss only, so not part of :tx_actions.
        post "link_subject_and_create_accounting_entry/:subject_id/:subject_type",
          to: "moss_bookings#link_subject_and_create_accounting_entry"
      end
      resources :moss_users, path: "moss/users", only: [:index, :show, :edit, :update] do
        collection { post :apply }
      end
      resources :moss_teams, path: "moss/teams", only: [:index, :show, :edit, :update] do
        collection { post :apply }
        member { post :apply_users }
      end
      resources :moss_departments, path: "moss/departments", only: [:index, :show, :edit, :update] do
        collection { post :apply }
        member do
          post :apply_teams
          post :apply_users
        end
      end
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
      resources :payment_returns, path: "payments/returns", only: [:index, :show, :edit, :update] do
        collection { post :apply }
      end
      get :fees, path: "fees", to: "fees#index", as: "fees"
      get :controlling, path: "controlling", to: "controlling#index", as: "controlling"
      get "controlling/budget", to: "budgets#index", as: "controlling_budget"
      get :sync, path: "sync", to: "sync#index", as: "fin_sync"
      get "sync/moss_api", to: "sync#moss_api", as: "fin_sync_moss_api"
      get "sync/moss_csv", to: "sync#moss_csv", as: "fin_sync_moss_csv"
      post "sync/purge", to: "sync#purge", as: "fin_sync_purge"
      post "sync/moss_api/runs", to: "sync_runs#create", as: "fin_sync_moss_api_runs"
      scope "sync/moss_api/runs/:id", constraints: {id: /\d+/} do
        get "", to: "sync_runs#show", as: "fin_sync_moss_api_run"
        post "apply", to: "sync_runs#apply", as: "fin_sync_moss_api_run_apply"
        post "cancel", to: "sync_runs#cancel", as: "fin_sync_moss_api_run_cancel"
        get "files/:name", to: "sync_runs#file", as: "fin_sync_moss_api_run_file", constraints: {name: %r{[^/]+}}
      end
      get :admin, path: "admin", to: "payment_references#index", as: "fin_admin"
      scope "admin" do
        get "finance_groups", to: "finance_groups#index", as: "fin_admin_finance_groups"
        # Named explicitly: the helper derived from the path would hide the area.
        patch "finance_groups", to: "finance_groups#apply",
          as: "fin_admin_apply_finance_groups"
        get "group_cost_centers", to: "group_cost_centers#index", as: "fin_admin_group_cost_centers"
        patch "group_cost_centers", to: "group_cost_centers#update",
          as: "fin_admin_save_group_cost_centers"
        get "payment_references", to: "payment_references#index", as: "fin_admin_payment_references"
        post "payment_references", to: "payment_references#generate",
          as: "fin_admin_generate_payment_references"
        post "payment_references/apply", to: "payment_references#apply",
          as: "fin_admin_apply_payment_references"
        get "payment_references/:id", to: "payment_references#show", as: "fin_admin_payment_reference",
          constraints: {id: /\d+/}
        patch "payment_references/:id", to: "payment_references#update", constraints: {id: /\d+/}
      end
      get :fin, path: "", to: "overview#index"

      get "bookkeeping", to: "bookkeeping#overview", as: "bookkeeping"
      scope "bookkeeping" do
        resources :ledger_accounts, param: :number, only: [:index, :show, :edit, :update],
          constraints: {number: /\d+/} do
          collection do
            post :apply
          end
        end
        # Cost-center numbers may contain letters, so no constraint.
        resources :cost_centers, param: :number, only: [:index, :show, :edit, :update] do
          collection do
            post :apply
          end
        end
        resources :personal_accounts, param: :number, only: [:index, :show, :edit, :update],
          constraints: {number: /\d+/} do
          collection do
            post :apply
          end
        end
        resources :booking_batches, only: [:index, :show] do
          collection do
            post :apply
          end
        end
        resources :bookings, only: [:index, :show, :edit, :update] do
          collection do
            post :apply
          end
          member do
            get :query_entries
          end
        end
      end

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
      get "reconciliation/unit_bookings", to: "unit_bookings#index", as: "reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/apply", to: "unit_bookings#apply",
        as: "apply_reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/bulk", to: "unit_bookings#bulk",
        as: "bulk_reconciliation_unit_bookings"
      post "reconciliation/unit_bookings/bulk/preview", to: "unit_bookings#bulk_preview",
        as: "bulk_preview_reconciliation_unit_bookings"
      if Rails.env.development?
        post "reconciliation/participant_fees/reset_links", to: "reconciliation#reset_links",
          as: "reset_links_reconciliation_participant_fees"
      end
    end

    namespace "contingent" do
      get :contingent, path: "", to: "wsjrdp_contingent#index"
      post :apply, to: "wsjrdp_contingent#apply"
      post :show_people_links, to: "wsjrdp_contingent#show_people_links"
      post :hide_people_links, to: "wsjrdp_contingent#hide_people_links"
      get :cmt, to: "wsjrdp_cmt#index"
      get :ist, to: "wsjrdp_ist#index"
      get :units, to: "wsjrdp_units#index"
      get "units/:id", to: "wsjrdp_units#show", as: :unit
      post "units/:id/apply", to: "wsjrdp_units#apply", as: :apply_unit
    end
  end
end
