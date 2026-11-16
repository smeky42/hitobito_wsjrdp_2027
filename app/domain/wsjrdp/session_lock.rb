# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A PostgreSQL advisory lock of the session (pg_try_advisory_lock), held
# around a block -- for work that must not run inside a transaction, such as
# document writes (each a Wsjrdp::LockedChange of its own, which takes
# transaction locks). The key is an Integer (a bigint lock key) or a String,
# hashed like Wsjrdp::LockedChange's keys (hashtextextended).
#
#   Wsjrdp::SessionLock.try(2_027_000_002) { run }               # false when taken
#   Wsjrdp::SessionLock.hold("deregistration_report:7", timeout: 8.seconds) { ... }
#
# Releasing never hides the block's error. A release that fails leaves the
# lock with a session that lives on in the pool, so the connection is then
# dropped: closing the session frees its locks, and the pool reconnects.
module Wsjrdp::SessionLock
  POLL_INTERVAL = 0.1

  module_function

  # Runs the block under the lock and answers true; answers false without
  # running it while somebody else holds the lock.
  def try(key, connection: ActiveRecord::Base.connection, &)
    sql = lock_sql(connection, key)
    return false unless acquire(connection, sql)

    hold_acquired(connection, sql, &)
    true
  end

  # Runs the block under the lock and answers what it answers, waiting up to
  # `timeout` (measured on the monotonic clock, which a frozen Time.current
  # does not stop) for somebody else to release it. Raises
  # Wsjrdp::LockedChange::Busy when the wait runs out.
  def hold(key, timeout:, connection: ActiveRecord::Base.connection, &)
    sql = lock_sql(connection, key)
    deadline = monotonic_now + timeout.to_f
    until acquire(connection, sql)
      raise Wsjrdp::LockedChange::Busy, "the lock #{key} is held by another session" if monotonic_now > deadline

      sleep POLL_INTERVAL
    end
    hold_acquired(connection, sql, &)
  end

  def hold_acquired(connection, sql)
    yield
  ensure
    release(connection, sql)
  end

  def acquire(connection, sql) = connection.select_value("SELECT pg_try_advisory_lock(#{sql})")

  def release(connection, sql)
    connection.select_value("SELECT pg_advisory_unlock(#{sql})")
  rescue => e
    Rails.logger.warn("Wsjrdp::SessionLock: releasing #{sql} failed (#{e.class}: #{e.message}); " \
      "dropping the connection, which frees the lock")
    begin
      connection.disconnect!
    rescue => disconnect_error
      Rails.logger.warn("Wsjrdp::SessionLock: dropping the connection failed: #{disconnect_error.class}")
    end
  end

  # The lock's key as SQL: a bigint as it is, a text through hashtextextended.
  def lock_sql(connection, key)
    key.is_a?(Integer) ? key.to_s : "hashtextextended(#{connection.quote(key.to_s)}, 0)"
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
