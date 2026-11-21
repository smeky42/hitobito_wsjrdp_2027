# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # The lookup's source for the table wsjrdp_credentials. It names every
  # account, so it comes last. A row is usable in state :active
  # (WsjrdpCredential#examine); the newest by created_at wins. The window
  # decides whether a version counts, never which one wins. Every row of
  # the account is examined, so that the answer can say in which states the
  # versions were.
  class DatabaseSource
    NAME = "database"

    attr_reader :keys, :kinds

    def initialize(keys: Keys.current, kinds: Kinds.current)
      @keys = keys
      @kinds = kinds
      freeze
    end

    def answer(kind, account_key)
      at = Time.current
      examinations = WsjrdpCredential.of_account(kind, account_key).newest_first
        .map { |row| row.examine(at: at, keys: keys, kinds: kinds) }
      Lookup::Answer.of(source: NAME, stage: keys.stage, examinations: examinations)
    end

    def inspect = "#<#{self.class.name} stage=#{Wsjrdp::Credentials.shown_stage(keys.stage)}>"
    alias_method :to_s, :inspect
  end
end
