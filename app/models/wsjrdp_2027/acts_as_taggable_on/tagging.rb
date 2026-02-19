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

    def after_tagging_save
      if previously_new_record?
        PaperTrail::Version.create(
          main: taggable, item: taggable,
          whodunnit: PaperTrail.request.whodunnit,
          event: "wsjrdp_add_tag",
          object_changes: YAML.dump({"tag" => [nil, tag.name]})
        )
      end
    end

    def after_tagging_destroy
      PaperTrail::Version.create(
        main: taggable, item: taggable,
        whodunnit: PaperTrail.request.whodunnit,
        event: "wsjrdp_remove_tag",
        object_changes: YAML.dump({"tag" => [tag.name, nil]})
      )
    end
  end
end
