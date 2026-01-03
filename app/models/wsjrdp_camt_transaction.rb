# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpCamtTransaction < ActiveRecord::Base
  include WsjrdpNumberHelper

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :fin_account,
    optional: true,
    class_name: "WsjrdpFinAccount"

  eur_attribute :amount_eur, cents_attr: :amount_cents

  def group
    @group ||= fetch_group
  end

  def try_skip?
    false
  end

  def skipped?
    false
  end

  def pre_booked?
    status != "BOOK"
  end

  def author_full_name
    nil
  end

  def short_dbtr
    s = [dbtr_name, dbtr_address, dbtr_iban].select { |e| !e.blank? }.join(", ")
    s.presence
  end

  private

  def fetch_group
    if subject.nil?
      Group.root
    elsif subject.primary_group_id.nil?
      Group.find(person.default_group_id)
    else
      subject.primary_group
    end
  end
end
