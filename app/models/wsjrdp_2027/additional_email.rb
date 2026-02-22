# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::AdditionalEmail
  extend ActiveSupport::Concern

  included do
    def can_show?(user: nil, action: :show)
      ability = user.present? ? Ability.new(user) : nil
      !hidden && (kind != "moss" || ability&.can?(:log, contactable))
    end

    def can_destroy?(user: nil)
      # ability = user.present? ? Ability.new(user) : nil
      return false if destroy_is_disabled
      kind.nil?
    end

    def can_edit_attribute?(attr, user: nil)
      case attr
      when :email, "email"
        true
      when :label, "label"
        true
      when :mailings, "mailings"
        !mailings_is_locked
      when :public, "public"
        !public_is_locked
      else
        true
      end
    end
  end
end
