# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpTransaction
  extend ActiveSupport::Concern
  include WsjrdpJsonbHelper

  included do
    jsonb_accessor :additional_info, :denylist_subject_candidates

    def subjects
      subject_list = accounting_entries.map(&:subject)
      subject_list << subject if subject_id.present? && subject.present?
      subject_list.uniq { |subject| subject.id }
    end

    def subject_without_accounting_entry
      if subject_id.blank? || subject.blank? || accounting_entries.map(&:subject_id).any?(subject_id)
        nil
      else
        subject
      end
    end

    def disallow_subject_candidate(subject)
      disallow_subject_id_and_type_candidate(subject.id, subject.class.name)
    end

    def disallow_subject_id_and_type_candidate(subject_id, subject_type)
      denylist = denylist_subject_candidates || []
      denylist << [subject_id, subject_type]
      self.denylist_subject_candidates = denylist
    end

    def ignored_link_subject_candidate_set
      ignored = denylist_subject_candidates&.dup || []
      ignored << [1, "Person"]  # deny admin account
      ignored.concat(subjects.map { |subject| [subject.id, subject.class.name] })
      Set.new(ignored)
    end

    def subject_candidates
      s = description_for_subject_candidates
      id_pat = /(CMT|UL|IST|BMT|YP|EXT|JPT|ID)[ ]([0-9 ]+)/
      ids = s.upcase.scan(id_pat).map { |role, id_s| id_s.delete(" ").to_i }
      ignored = ignored_link_subject_candidate_set
      ids = ids.reject { |id| ignored.include?([id, "Person"]) }.sort.uniq
      ids.map { |id| Person.find_by(id: id) }.compact
    end

    def accounting_entries_for_subject(amount_cents: nil)
      return [] if subject.nil?
      entries = subject.accounting_entries
      entries = entries.select { |e| e.amount_cents == amount_cents } unless amount_cents.nil?
      entries
    end

    def accounting_entries_for_subject_with_matching_amount
      accounting_entries_for_subject(amount_cents: amount_cents)
    end
  end
end
