# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::SessionLock do
  let(:key) { "session_lock_spec:#{SecureRandom.hex(4)}" }

  describe ".hold" do
    it "holds the lock around the block, answers its value and releases it" do
      answer = described_class.hold(key, timeout: 1.second) { !session_lock_free?(key) }

      expect(answer).to be(true)
      expect(session_lock_free?(key)).to be(true)
    end

    it "releases the lock when the block raises, keeping the block's error" do
      expect { described_class.hold(key, timeout: 1.second) { raise ArgumentError, "inner" } }
        .to raise_error(ArgumentError, "inner")
      expect(session_lock_free?(key)).to be(true)
    end

    it "raises Busy when another session holds the lock past the timeout" do
      holding_session_lock(key) do
        expect { described_class.hold(key, timeout: 0.seconds) { raise "not run" } }
          .to raise_error(Wsjrdp::LockedChange::Busy)
      end
    end

    it "drops the connection when the release fails, which frees the lock" do
      connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter, quote: "'k'")
      allow(connection).to receive(:select_value).with(/pg_try_advisory_lock/).and_return(true)
      allow(connection).to receive(:select_value).with(/pg_advisory_unlock/).and_raise(ActiveRecord::StatementInvalid)
      expect(connection).to receive(:disconnect!)

      expect(described_class.hold(key, timeout: 1.second, connection: connection) { :done }).to eq(:done)
    end
  end

  describe ".try" do
    it "runs the block and answers true, or answers false while the lock is taken" do
      ran = false
      expect(described_class.try(key) { ran = true }).to be(true)
      expect(ran).to be(true)

      holding_session_lock(key) do
        expect(described_class.try(key) { raise "not run" }).to be(false)
      end
    end

    it "takes an Integer key as the lock key itself" do
      expect(described_class.lock_sql(ActiveRecord::Base.connection, 2_027_000_002)).to eq("2027000002")
    end
  end
end
