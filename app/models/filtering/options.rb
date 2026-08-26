# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # Where a reference/enum attribute's [value, label] pairs come from. All
  # variants are LAZY: declaring them (at schema definition / boot time) never
  # touches the database; the values are computed when the catalog is rendered.
  class Options
    # From an ActiveRecord relation: value/label per record. `label` may be a
    # Proc (record -> String) or a symbol (method name).
    def self.from(relation, value:, label:)
      new(-> {
        relation.map do |record|
          l = label.is_a?(Proc) ? label.call(record) : record.public_send(label)
          [record.public_send(value).to_s, l.to_s]
        end
      })
    end

    # From an arbitrary lambda returning [[value, label], ...].
    def self.values(callable)
      new(-> { callable.call.map { |v, l| [v.to_s, (l || v).to_s] } })
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

    def initialize(pairs_proc)
      @pairs_proc = pairs_proc
    end

    def pairs
      @pairs_proc.call
    end

    # Catalog form. Inline only for now; a {mode: "remote", endpoint: ...}
    # variant can be added when an option set outgrows inline shipping.
    def descriptor
      {mode: "inline", values: pairs}
    end
  end
end
