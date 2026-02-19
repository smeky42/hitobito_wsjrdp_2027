# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaperTrail::Events::Base
  extend ActiveSupport::Concern

  included do
    class_eval do
      def load_changes_in_latest_version
        if @in_after_callback
          changes = @record.saved_changes
          get_change = ->(record, key) { record.try("saved_change_to_#{key}") }
        else
          changes = @record.changes
          get_change = ->(record, key) { record.try("#{key}_change") }
        end
        if @record.class.respond_to?(:stored_attributes)
          stored_attributes = @record.class.stored_attributes
          stored_attributes.each do |db_column, keys|
            keys.each do |key|
              change = get_change.call(@record, key)
              changes[key.to_s] = change unless change.nil? || change[0] == change[1]
            end
          end
        end
        changes
      end
    end
  end
end
