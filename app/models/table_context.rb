# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Tells a detail partial (a DATEV booking, a ledger account, a supplier …)
# whether it is being rendered on its OWN page or nested inside a table row's
# expandable detail, and how deep. The shared table (shared/_expandable_table)
# hands one of these to every detail it renders; the SAME object is produced for
# a directly-rendered detail and for a lazily-loaded one (turbo frame -- the
# level travels in the frame URL as `_lvl`, see the widget + the bookkeeping
# detail actions), so a partial reads its situation the same way either way.
#
#   ctx.root?    -- true on a dedicated page (level 0)
#   ctx.nested?  -- true inside a table row's detail (level >= 1)
#   ctx.level    -- 0 = page, 1 = a row's detail, 2 = a table inside a detail, …
#   ctx.lazy?    -- the detail was (or will be) loaded into a turbo frame
#
# A partial that itself embeds another expandable table passes ctx.level on as
# that table's `detail_level`, so nesting keeps counting up.
class TableContext
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
