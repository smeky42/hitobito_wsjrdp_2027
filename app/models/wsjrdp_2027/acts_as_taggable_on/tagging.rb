# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::ActsAsTaggableOn::Tagging
  extend ActiveSupport::Concern

  included do
    after_save :after_tagging_save
    after_destroy :after_tagging_destroy

    private

    # The log entry of the tag's person or group (Wsjrdp::LogEvents): the
    # tag's name in wsjrdp_data and, as before it, in object_changes.
    def after_tagging_save
      log_tagging("wsjrdp_add_tag", [nil, tag.name]) if previously_new_record?
    end

    def after_tagging_destroy
      log_tagging("wsjrdp_remove_tag", [tag.name, nil])
    end

    def log_tagging(event, change)
      Wsjrdp::LogEntry.record!(taggable, event, {"tag_name" => tag.name},
        object_changes: YAML.dump({"tag" => change}))
    end
  end
end
