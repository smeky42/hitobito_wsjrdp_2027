# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

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

          get "upload" => "person/upload#index"
          put "upload" => "person/upload#index"
          get "upload/show_contract" => "person/upload#show_contract"
          get "upload/show_medical" => "person/upload#show_medical"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_passport" => "person/upload#show_passport"
          get "upload/show_recommendation" => "person/upload#show_recommendation"
          get "upload/show_data_agreement" => "person/upload#show_data_agreement"
          get "upload/show_photo_permission" => "person/upload#show_photo_permission"


          get "medical" => "person/medical#show"
          get "medical/edit" => "person/medical#edit"
          put "medical" => "person/medical#update"

          get "status" => "person/status#show"
          get "status/edit" => "person/status#edit"
          put "status" => "person/status#update"
        end
      end
    end
  end
end
