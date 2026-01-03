# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

  namespace :public do
    get "statistics", to: "statistics#index"
  end

  language_scope do
    resources :groups do
      resources :people, except: [:new, :create] do
        member do
          post :send_password_instructions
          put :primary_group

          get "print" => "person/print#index"
          put "print" => "person/print#index"
          get "print/preview" => "person/print#preview"
          get "print/submit" => "person/print#submit"

          get "accounting" => "person/accounting#index"
          post "accounting" => "person/accounting#create"

          get "upload" => "person/upload#index"
          put "upload" => "person/upload#index"
          get "upload/show_registration_generated" => "person/upload#show_registration_generated"
          get "upload/show_contract" => "person/upload#show_contract"
          get "upload/show_sepa" => "person/upload#show_sepa"
          get "upload/show_medical" => "person/upload#show_medical"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_passport" => "person/upload#show_passport"
          get "upload/show_recommendation" => "person/upload#show_recommendation"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_photo_permission" => "person/upload#show_photo_permission"
          get "upload/show_good_conduct" => "person/upload#show_good_conduct"
          delete "upload/delete/:what" => "person/upload#destroy"

          get "medical" => "person/medical#show"
          get "medical/edit" => "person/medical#edit"
          put "medical" => "person/medical#update"

          get "status" => "person/status#show"
          get "status/edit" => "person/status#edit"
          put "status" => "person/status#update"
          post "status/activate_planned_custom_installments" => "person/status#activate_planned_custom_installments"
          post "status/delete_planned_custom_installments" => "person/status#delete_planned_custom_installments"
          post "status/review_documents" => "person/status#review_documents"
          post "status/approve_documents" => "person/status#approve_documents"

          get "unit" => "person/unit#show"
          post "unit/fill_cluster_code" => "person/unit#fill_cluster_code"
          post "unit/clear_cluster_code" => "person/unit#clear_cluster_code"
        end

        resources :accounting_entries, path: "/fin/ae", shallow: true, only: [:show, :update]
        resources :wsjrdp_direct_debit_pre_notifications, path: "/fin/pn", shallow: true, only: [:show, :update]
      end

      get "map" => "group/map#index"
    end

    get "groups/:group_id/statistics/data", to: "group/statistics#statistics_data", defaults: {format: :json}
  end

  namespace :fin do
    resources :wsjrdp_camt_transactions, path: "tx", shallow: true, only: [:show, :update]
    resources :wsjrdp_fin_accounts, path: "acc", shallow: true, only: [:show, :update]
  end
end
