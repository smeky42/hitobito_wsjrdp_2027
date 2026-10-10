# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Person < Base
    class Finance < Base
      # Who sees which page: PersonFinancePagesHelper.
      # Each also in the URL of the primary group (alt).
      tab "people.finance.tabs.fee", :person_fee_path_with_group,
        alt: [:fee_group_person_path, :finance_group_person_path, :accounting_group_person_path],
        if: ->(view, *path_args) { view.person_fee_page_visible?(path_args.last) }
      tab "people.finance.tabs.spend", :person_spend_path_with_group, alt: [:spend_group_person_path],
        if: ->(view, *path_args) { view.person_spend_visible?(path_args.last) }
      tab "people.finance.tabs.deregistration", :person_deregistration_path_with_group,
        alt: [:deregistration_group_person_path], if: :log

      self.parent_sheet = Sheet::Person

      def model_name
        @model_name ||= "person"
      end

      def title
        "#{entry} - Finanzen"
      end
    end
  end
end
