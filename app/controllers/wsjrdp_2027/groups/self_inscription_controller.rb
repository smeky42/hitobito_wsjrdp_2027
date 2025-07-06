module Wsjrdp2027::Groups::SelfInscriptionController
  extend ActiveSupport::Concern

  included do
    def create
      render "show", status: :forbidden
    end
  end
end
