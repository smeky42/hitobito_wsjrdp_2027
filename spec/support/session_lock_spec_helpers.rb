# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A Wsjrdp::SessionLock key seen from another session, as a second process
# would hold or probe it.
module SessionLockSpecHelpers
  # Holds the lock on another connection around the block.
  def holding_session_lock(key)
    with_other_connection do |other|
      sql = Wsjrdp::SessionLock.lock_sql(other, key)
      other.select_value("SELECT pg_advisory_lock(#{sql})")
      begin
        yield
      ensure
        other.select_value("SELECT pg_advisory_unlock(#{sql})")
      end
    end
  end

  # Whether another connection could take the lock now.
  def session_lock_free?(key)
    with_other_connection do |other|
      sql = Wsjrdp::SessionLock.lock_sql(other, key)
      taken = other.select_value("SELECT pg_try_advisory_lock(#{sql})")
      other.select_value("SELECT pg_advisory_unlock(#{sql})") if taken
      taken
    end
  end

  def with_other_connection
    other = ActiveRecord::Base.connection_pool.checkout
    yield other
  ensure
    ActiveRecord::Base.connection_pool.checkin(other) if other
  end
end

RSpec.configure { |config| config.include SessionLockSpecHelpers }
