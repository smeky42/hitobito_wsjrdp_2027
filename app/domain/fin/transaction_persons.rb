# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The persons linked to a transaction, as one text in SQL ("First Last, ..."),
# so a table can show, sort and filter by them alike: of a bank transaction its
# person and the persons of its contribution bookings, of a Moss transaction
# the persons of its bookings.
module Fin::TransactionPersons
  NAME_SQL = "concat_ws(' ', NULLIF(p.first_name, ''), NULLIF(p.last_name, ''))"

  module_function

  # `t`: the name or alias of the camt transactions table in the query.
  def camt_sql(t)
    <<~SQL.squish
      (SELECT string_agg(DISTINCT #{NAME_SQL}, ', ') FROM people p
       WHERE p.id IN (SELECT #{t}.subject_id WHERE #{t}.subject_type = 'Person'
         UNION SELECT ae.subject_id FROM accounting_entries ae
         WHERE ae.camt_transaction_id = #{t}.id AND ae.subject_type = 'Person'))
    SQL
  end

  # `t`: the name or alias of the Moss transactions table in the query.
  def moss_sql(t)
    <<~SQL.squish
      (SELECT string_agg(DISTINCT #{NAME_SQL}, ', ') FROM people p
       WHERE p.id IN (SELECT b.contribution_subject_id FROM moss_bookings b
         WHERE b.moss_transaction_id = #{t}.id AND b.contribution_subject_type = 'Person'))
    SQL
  end
end
