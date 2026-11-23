# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # One part of the tree (doc/fin/sync.md, "A part"). A subclass sets key
  # and depends_on and fills in the three steps:
  #
  # - fetch(input): reads the source (the Moss client) and returns
  #   {name => plain JSON}; each entry becomes one data file.
  # - plan(data): compares with the database and returns a Plan; writes
  #   nothing.
  # - apply(data, plan): writes the plan's changes and returns the rows
  #   written (Stats). The run calls it in a transaction, after planning
  #   again and comparing the digest.
  class Part
    # source: what the part reads, e.g. "moss_api" (a run's source).
    class_attribute :key, :source, :depends_on, instance_writer: false
    self.depends_on = []

    def self.label = I18n.t("fin.sync.parts.#{key}._label")

    attr_reader :context

    def initialize(context)
      @context = context
    end

    def fetch(_input) = raise(NotImplementedError)

    def plan(_data) = raise(NotImplementedError)

    def apply(_data, _plan) = raise(NotImplementedError)

    private

    # items: {record key => text} of the records concerned.
    def hint(code, items = {}, **values) = notice(Plan::HINT, code, items, **values)

    def important(code, items = {}, **values) = notice(Plan::IMPORTANT, code, items, **values)

    def warning(code, items = {}, **values) = notice(Plan::WARNING, code, items, **values)

    def notice(level, code, items, **values)
      Plan::Warning.new(level: level, code: code, items: items.sort.to_h,
        message: I18n.t("fin.sync.notices.#{code}", count: items.size, **values))
    end
  end
end
