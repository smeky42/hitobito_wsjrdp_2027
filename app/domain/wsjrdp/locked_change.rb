# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Runs a block in a transaction of its own, under locks that are all taken
# before it runs (doc/wsjrdp/locked_change.md):
#
#   Wsjrdp::LockedChange.run(rows: [person], keys: ["..."]) do |change|
#     ...                          # fast database work only
#     change.after_commit { ... }  # mails, jobs, answers
#   end
#
# rows are records, locked FOR NO KEY UPDATE (reloaded; they must have no
# unsaved changes): other updates of them wait, reads and inserts that refer
# to them do not. keys are strings, each an advisory lock of the transaction
# (pg_advisory_xact_lock on hashtextextended of the key). The rows come
# first, ordered by table and id, then the keys, ordered by their hash; every
# change takes its locks in this one order and takes none later, so two
# changes never wait for each other in a circle.
#
# A lock that is not free within timeout raises Busy. The block must not
# send mails or call other services -- after_commit is for that -- and must
# not lock further rows; on_rollback undoes what lies outside the database
# (e.g. files). A change does not run inside an open transaction: its commit
# would not be one. Inside a transaction that is not joinable (the one
# around a spec) it runs in a savepoint, and the end of the block counts as
# the commit.
class Wsjrdp::LockedChange
  DEFAULT_TIMEOUT = 8.seconds

  # A lock was not free within the timeout.
  class Busy < ActiveRecord::LockWaitTimeout; end

  # run was called inside an open transaction.
  class NestedTransaction < StandardError; end

  def self.run(rows: [], keys: [], timeout: DEFAULT_TIMEOUT, &block)
    new(rows: rows, keys: keys, timeout: timeout).run(&block)
  end

  # The numbers of the advisory locks of keys, without duplicates, in the
  # order they are taken.
  def self.lock_numbers(keys)
    keys = Array(keys).map(&:to_s).uniq
    return [] if keys.empty?

    sql = ActiveRecord::Base.sanitize_sql_array(
      ["SELECT DISTINCT hashtextextended(k, 0) AS h FROM unnest(ARRAY[?]::text[]) AS k ORDER BY h", keys]
    )
    ActiveRecord::Base.connection.select_values(sql).map(&:to_i)
  end

  def initialize(rows:, keys:, timeout:)
    @rows = Array(rows).compact.uniq.sort_by { |row| [row.class.table_name, row.id] }
    @keys = Array(keys)
    @timeout = timeout
    @after_commit = []
    @on_rollback = []
  end

  def after_commit(&block) = @after_commit << block

  def on_rollback(&block) = @on_rollback << block

  def run
    connection = ActiveRecord::Base.connection
    inside = connection.transaction_open?
    if inside && connection.current_transaction.joinable?
      raise NestedTransaction, "a locked change runs in a transaction of its own"
    end

    result = nil
    completed = false
    begin
      ActiveRecord::Base.transaction(requires_new: true) do
        previous = connection.select_value("SHOW lock_timeout") if inside
        connection.execute("SET LOCAL lock_timeout = #{Integer(@timeout.in_milliseconds)}")
        @rows.each { |row| row.lock!("FOR NO KEY UPDATE") }
        self.class.lock_numbers(@keys).each { |number| connection.execute("SELECT pg_advisory_xact_lock(#{number})") }
        result = yield self
        connection.execute("SET LOCAL lock_timeout = #{connection.quote(previous)}") if inside
        completed = true
      end
    rescue ActiveRecord::LockWaitTimeout => e
      rolled_back
      raise if e.is_a?(Busy)

      raise Busy.new(e.message, sql: e.sql, binds: e.binds)
    rescue Exception # rubocop:disable Lint/RescueException -- undo the files on any abort, then re-raise
      rolled_back
      raise
    end
    # ActiveRecord::Rollback in the block rolls back without an error.
    unless completed
      rolled_back
      return nil
    end

    @after_commit.each(&:call)
    result
  end

  private

  def rolled_back = @on_rollback.each(&:call)
end
