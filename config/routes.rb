# frozen_string_literal: true

Rails.application.routes.draw do
  extend LanguageRouteScope

  language_scope do
    
    resources :groups do
      resources :people, except: [:new, :create] do
        member do
          get 'upload' => 'person/upload#index'
          put 'upload' => 'person/upload#index'
        end
      end
    end
  end
end
