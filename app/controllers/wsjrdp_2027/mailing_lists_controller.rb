# frozen_string_literal: true

module Wsjrdp2027::MailingListsController
  extend ActiveSupport::Concern

  included do
    # The original code checked for :update permission on the parent group.
    # We change this to check for :index_mailing_lists permission instead.

    private

    def list_entries
      scope = super.list
      can?(:index_mailing_lists, parent) ? scope : scope.subscribable
    end
  end
end
