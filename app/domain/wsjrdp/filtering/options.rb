# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # Where a reference/enum attribute's [value, label] pairs come from. All
  # variants are LAZY: declaring them (at schema definition / boot time) never
  # touches the database; the values are computed when the catalog is rendered.
  class Options
    # From an ActiveRecord relation: value/label per record. `label` may be a
    # Proc (record -> String) or a symbol (method name). Pass the relation as a
    # lambda (`-> { Model.order(:number) }`) when the schema is declared at
    # boot: building a relation with `order(:column)` already reads the table's
    # columns, which fails while the app boots against a database without the
    # wagon's tables (e.g. an eager-loading asset build in CI).
    def self.from(relation, value:, label:)
      new(-> {
        relation = relation.call if relation.respond_to?(:call)
        relation.map do |record|
          l = label.is_a?(Proc) ? label.call(record) : record.public_send(label)
          [record.public_send(value).to_s, l.to_s]
        end
      })
    end

    # From an arbitrary lambda returning [[value, label], ...] -- or [value,
    # label, prefix]: a prefix shown muted and light before the label (a
    # person's role and id before the name), searched and spelled out with it.
    # id_search: the values are ids; a search of digits looks for them only
    # (shared/wsjrdp/_chips_combobox_js).
    def self.values(callable, id_search: false)
      new(-> {
        callable.call.map do |v, l, prefix|
          pair = [v.to_s, (l || v).to_s]
          prefix.nil? ? pair : pair << prefix.to_s
        end
      }, id_search: id_search)
    end

    # Merge several Options. On duplicate values the first INFORMATIVE label
    # wins: a label that adds nothing beyond the value itself (e.g. a nameless
    # DATEV creditor number stub, "700019 ") yields to a later, richer one (the
    # supplier's "700019 Förderkreis ..."). The result is ordered by value (short
    # numbers first, i.e. G/L accounts before the 6-digit creditors).
    def self.merge(*options)
      new(-> {
        seen = {}
        options.flat_map(&:pairs).each do |value, label|
          informative = label.present? && label.strip != value
          seen[value] = [label, informative] if !seen.key?(value) || (informative && !seen[value][1])
        end
        seen.map { |value, (label, _)| [value, label] }
          .sort_by { |value, _| [value.length, value] }
      })
    end

    def initialize(pairs_proc, id_search: false)
      @pairs_proc = pairs_proc
      @id_search = id_search
    end

    # Computed once per request: a page asks for them several times (the
    # builder's catalog, the chips' full catalog, preset groups), and an option
    # set can be large (every person with a debit). Outside a request -- a spec,
    # a script -- every call computes afresh, so nothing stale is ever seen.
    def pairs
      return @pairs_proc.call unless RequestStore.active?

      cache = (RequestStore.store[:wsjrdp_filter_option_pairs] ||= {}.compare_by_identity)
      cache.fetch(self) { cache[self] = @pairs_proc.call }
    end

    # Catalog form. Inline only for now; a {mode: "remote", endpoint: ...}
    # variant can be added when an option set outgrows inline shipping.
    def descriptor
      {mode: "inline", values: pairs, **(@id_search ? {id_search: true} : {})}
    end
  end
end
