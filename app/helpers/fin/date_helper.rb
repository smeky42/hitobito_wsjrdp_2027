# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE date format of the Finanzen pages: the date cells of the expandable
# tables (Moss transactions, Buchungen, the wallet statement, the camt
# statement) and the dates of the overview pages all go through this helper, so
# the notation is written down exactly once -- in FIN_DATE_FORMAT.
#
# Each format comes in two shapes, because the callers differ: a table cell
# hands a nil on to the widget, which renders the blank itself, while a figure
# row or a standing table row has to write the em dash into its own text. The
# `_or_dash` variants are the latter.
module Fin::DateHelper
  # Day precision, German notation -- what every finance page shows.
  FIN_DATE_FORMAT = "%d.%m.%Y"
  # The same date plus the time of day, to the minute.
  FIN_DATE_TIME_FORMAT = "#{FIN_DATE_FORMAT} %H:%M".freeze
  # What stands where there is no date at all.
  FIN_BLANK_DATE = "—"

  # A date, or nil when there is none (the caller renders the blank).
  def fin_date(date) = date&.strftime(FIN_DATE_FORMAT)

  # A date, or the em dash the pages write where there is none.
  def fin_date_or_dash(date) = fin_date(date) || FIN_BLANK_DATE

  # A timestamp, or nil when there is none.
  def fin_date_time(time) = time&.strftime(FIN_DATE_TIME_FORMAT)

  # A timestamp, or the em dash.
  def fin_date_time_or_dash(time) = fin_date_time(time) || FIN_BLANK_DATE
end
