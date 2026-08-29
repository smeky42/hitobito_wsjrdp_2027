# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Where a table's :remember fields are mirrored (D7). A store maps a store key
# (see Wsjrdp::TableStatePolicy#store_key_for) to a small Hash of
# `field short => wire value`; the resolver reads it when the URL param is
# absent and writes back the resolved (allow-listed) value.
#
#   read(key)               -> Hash | nil
#   write(key, hash)        -> replaces the entry (an empty hash deletes it)
#   delete(key)             -> forgets one table (the per-table reset, D3)
#   delete_all(key_prefix)  -> forgets a whole page / controller
#
# Implementations: Session (the general one) and Cookie (JS-written UI chrome
# only -- see the caveat on Wsjrdp::TableStateStore::Cookie). A per-person DB
# store later implements the same four methods.
module Wsjrdp::TableStateStore
end
