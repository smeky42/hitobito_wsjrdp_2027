# frozen_string_literal: true

module Wsjrdp2027::Event
  extend ActiveSupport::Concern

  included do
    self.supports_invitations = false
  end
end
