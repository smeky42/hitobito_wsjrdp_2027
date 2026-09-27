# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The key of a service token is shown only in the answer to the request that
  # makes it -- on creation and on "Token neu erzeugen". It never goes through
  # the flash or the session: the session lives in the database.
  #
  # Both answers show the key above the token's attributes
  # (service_tokens/_plain_token). A Turbo form submission must be answered by
  # a redirect or a Turbo Stream, so creation through Turbo gets a stream that
  # puts them where the form was; "Token neu erzeugen" is a plain POST (its
  # button is a data-method link) and gets the show page with the key.
  #
  # The new form carries how the key is stored (token_kind), and for a key
  # made in another stage its stage, token hash and optionally the
  # fingerprint of its secret (adopted_stage, adopted_token,
  # adopted_fingerprint); such a token has
  # no key to show and is answered as the core answers.
  module ServiceTokensController
    def self.prepended(base)
      base.permitted_attrs += [:token_kind, :adopted_stage, :adopted_token, :adopted_fingerprint,
        :acting_person_id,
        {wagon_scopes: []}]
    end

    def create
      super do |format|
        next unless entry.persisted? && entry.plain_token

        keep_notice_on_this_page
        # A template, not streams built here: the entry is decorated as
        # render starts, and the attributes need the decorator.
        format.turbo_stream { render "service_tokens/create" }
        format.html { render "service_tokens/plain_token" }
      end
    end

    def regenerate_token
      authorize!(:regenerate_token, entry)
      entry.regenerate_token!(params[:kind])
      flash.now[:notice] = t("service_tokens.regenerate_token.flash.success", model: full_entry_label)
      render "service_tokens/plain_token"
    rescue ActiveRecord::RecordInvalid
      redirect_to group_service_token_path(entry.layer, entry), alert: entry.errors.full_messages.to_sentence
    end

    private

    # Only an admin sets the acting person and the finance scopes: anyone
    # else's acting person is dropped and the stored finance scopes are kept,
    # and the model checks the assigner once more (Wsjrdp2027::ServiceToken).
    # The extras work only with an acting person, so they go with it (the
    # form asks first).
    def assign_attributes
      keep_admin_only_values unless ::ServiceToken.acting_person_admin?(current_person)
      super
      entry.acting_person_assigner = current_person
      entry.drop_extra_scopes if entry.acting_person_id.nil?
    end

    def keep_admin_only_values
      attrs = params[:service_token]
      return unless attrs

      attrs.delete(:acting_person_id)
      return unless attrs.key?(:wagon_scopes)

      finance = ->(scope) { Wsjrdp2027::ServiceTokenScopes.finance?(scope) }
      attrs[:wagon_scopes] = Array(attrs[:wagon_scopes]).reject(&finance) + entry.scopes.select(&finance)
    end

    # The success notice belongs to this answer, not to the next page.
    def keep_notice_on_this_page
      flash.now[:notice] = flash[:notice]
    end
  end
end
