# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The waiting of two changes for each other: locked_change_concurrency_spec.
describe Wsjrdp::LockedChange do
  let(:person) { people(:yp_a_1) }

  let(:locked_ids) { [] }

  def statements
    sqls = []
    callback = lambda do |*, payload|
      sqls << payload[:sql]
      if payload[:sql].include?("FOR NO KEY UPDATE")
        locked_ids << Array(payload[:type_casted_binds]).first
      end
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  it "runs the block and answers its value" do
    expect(described_class.run { 42 }).to eq(42)
  end

  it "refuses to run inside an open transaction" do
    ActiveRecord::Base.transaction do
      expect { described_class.run { 1 } }.to raise_error(described_class::NestedTransaction)
    end
  end

  it "locks the rows first, then the keys, each in one order" do
    other = people(:yp_a_2)
    sqls = statements { described_class.run(rows: [person, other], keys: %w[b a b c]) {} }

    row_locks = sqls.grep(/FOR NO KEY UPDATE/)
    advisory = sqls.grep(/pg_advisory_xact_lock\(/).map { |sql| sql[/\((-?\d+)\)/, 1].to_i }
    expect(row_locks.size).to eq(2)
    expect(locked_ids).to eq([person.id, other.id].sort)
    expect(advisory).to eq(described_class.lock_numbers(%w[a b c]))
    expect(advisory).to eq(advisory.sort)
    expect(sqls.index { |sql| sql.include?("FOR NO KEY UPDATE") })
      .to be < sqls.index { |sql| sql.include?("pg_advisory_xact_lock(") }
  end

  it "takes the same lock for the same key" do
    expect(described_class.lock_numbers(%w[x x])).to eq(described_class.lock_numbers(%w[x]))
    expect(described_class.lock_numbers(%w[x y]).uniq.size).to eq(2)
  end

  it "reloads the locked rows" do
    Person.where(id: person.id).update_all(nickname: "Neu")

    described_class.run(rows: [person]) {}

    expect(person.nickname).to eq("Neu")
  end

  it "runs after_commit after the block and not on_rollback" do
    calls = []
    described_class.run do |change|
      change.after_commit { calls << :commit }
      change.on_rollback { calls << :rollback }
      calls << :block
    end

    expect(calls).to eq(%i[block commit])
  end

  it "runs on_rollback when the block raises, and undoes its writes" do
    calls = []
    expect {
      described_class.run(rows: [person]) do |change|
        change.after_commit { calls << :commit }
        change.on_rollback { calls << :rollback }
        person.update!(nickname: "Weg")
        raise "boom"
      end
    }.to raise_error("boom")

    expect(calls).to eq([:rollback])
    expect(person.reload.nickname).not_to eq("Weg")
  end

  it "runs on_rollback for ActiveRecord::Rollback and answers nil" do
    calls = []
    result = described_class.run do |change|
      change.on_rollback { calls << :rollback }
      raise ActiveRecord::Rollback
    end

    expect(result).to be_nil
    expect(calls).to eq([:rollback])
  end

  it "leaves the lock timeout of the enclosing transaction as it was" do
    before = ActiveRecord::Base.connection.select_value("SHOW lock_timeout")

    described_class.run(timeout: 0.5.seconds) do
      expect(ActiveRecord::Base.connection.select_value("SHOW lock_timeout")).to eq("500ms")
    end

    expect(ActiveRecord::Base.connection.select_value("SHOW lock_timeout")).to eq(before)
  end

  it "refuses a row with unsaved changes" do
    person.nickname = "Ungespeichert"

    expect { described_class.run(rows: [person]) {} }.to raise_error(/unpersisted changes/)
  end
end
