# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# WHERE a finance value is being shown -- the argument every detail formatter
# (Fin::AttrFormatHelper) and every section of a detail partial
# (Fin::DetailHelper) receives besides the record itself.
#
#   mode           :regular  the record's own page, :embedded  a table row's
#                            detail pane; the HOST decides, it is not derived
#                            from the nesting level
#   table_context  the Wsjrdp::TableContext when the detail sits in a table
#                  (level, lazy), nil on a page
#   raw_source     the jsonb column a raw block is rendering (Fin::DetailHelper
#                  sets it per block), nil everywhere else
#
# A controller's #show builds .regular for the page and .embedded(...) for a
# turbo-frame request; a table that renders a detail directly passes
# .embedded(ctx) from its (row, ctx) lambda. #level / #in_table? / #lazy?
# therefore read the same way in both paths (doc/wsjrdp/expandable_table.md §4).
class Fin::AttrFormatContext
  MODES = %i[regular embedded].freeze

  attr_reader :mode, :table_context, :raw_source

  def initialize(mode:, table_context: nil, raw_source: nil)
    raise ArgumentError, "mode must be one of #{MODES.join(", ")}" unless MODES.include?(mode)
    @mode = mode
    @table_context = table_context
    @raw_source = raw_source
  end

  def regular? = mode == :regular

  def embedded? = mode == :embedded

  # 0 on a page, 1 in a row's detail, 2 in a table inside a detail, ...
  def level = table_context&.level.to_i

  # Inside a table row's detail.
  def in_table? = table_context&.nested? || false

  # Arrived through a turbo frame.
  def lazy? = table_context&.lazy? || false

  def self.regular = new(mode: :regular)

  def self.embedded(table_context) = new(mode: :embedded, table_context: table_context)

  # The same situation, with the jsonb column a raw block is rendering.
  def with_raw_source(source) = self.class.new(mode:, table_context:, raw_source: source)
end
