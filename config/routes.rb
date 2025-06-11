# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

  language_scope do
    resources :groups do
      resources :people, except: [:new, :create] do
        member do
          get "upload" => "person/upload#index"
          put "upload" => "person/upload#index"
          get "upload/show_contract" => "person/upload#show_contract"
          get "upload/show_contract" => "person/upload#show_contract"
          get "upload/show_medical" => "person/upload#show_medical"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_passport" => "person/upload#show_passport"
          get "upload/show_recommendation" => "person/upload#show_recommendation"
        end
      end
    end
  end
end
