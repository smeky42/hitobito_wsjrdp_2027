# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Tells a detail partial (a DATEV booking, a ledger account, a supplier …)
# whether it is being rendered on its OWN page or nested inside a table row's
# expandable detail, and how deep. The shared table (shared/wsjrdp/_expandable_table)
# hands one of these to every detail it renders; the SAME object is produced for
# a directly-rendered detail and for a lazily-loaded one (turbo frame -- the
# level travels in the frame URL as the table's `l` param and is resolved back by
# the target controller's own policy into that table's state, see
# Wsjrdp::TableState#level and Fin::BookkeepingSummaries), so a partial reads its
# situation the same way either way.
#
#   ctx.root?    -- true on a dedicated page (level 0)
#   ctx.nested?  -- true inside a table row's detail (level >= 1)
#   ctx.level    -- 0 = page, 1 = a row's detail, 2 = a table inside a detail, …
#   ctx.lazy?    -- the detail was (or will be) loaded into a turbo frame
#
# A partial that itself embeds another expandable table does not thread the level
# through the view: that table's own policy declares where its level comes from
# (`level: {default: -> { summary_table_state.level }}`), so nesting keeps
# counting up through the state.
class Wsjrdp::TableContext
  attr_reader :level

  def initialize(level: 0, lazy: false)
    @level = level.to_i
    @lazy = lazy
  end

  def root? = @level.zero?

  def nested? = @level.positive?

  def lazy? = @lazy

  # The context for a detail rendered one level below this table.
  def self.for_detail(table_level, lazy:)
    new(level: table_level.to_i + 1, lazy: lazy)
  end
end
