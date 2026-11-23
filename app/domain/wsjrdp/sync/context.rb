# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # What a run hands every part: the data of all its parts so far (by part
  # key), the time of the step and who started it.
  Context = Data.define(:data, :now, :actor) do
    def data_of(key) = data[key]
  end
end
