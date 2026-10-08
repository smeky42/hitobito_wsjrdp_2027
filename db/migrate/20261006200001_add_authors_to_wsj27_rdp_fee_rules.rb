# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Who did what to a fee rule: created it (planned), changed it last,
# activated it, deleted it (replaced by a newly activated rule, or a plan
# discarded). Written by Wsjrdp2027::ParticipationFee and the installment plan
# form of the person's Beitrag page; the rules from before stay NULL. Deleting
# the author's person keeps the rule and empties the author.
class AddAuthorsToWsj27RdpFeeRules < ActiveRecord::Migration[7.1]
  def change
    %i[created_by updated_by activated_by deleted_by].each do |author|
      add_reference :wsj27_rdp_fee_rules, author, type: :integer, null: true,
        foreign_key: {to_table: :people, on_delete: :nullify}
    end
  end
end
