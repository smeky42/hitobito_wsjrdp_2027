#  Copyright (c) 2012-2024, Pfadibewegung Schweiz. This file is part of
#  hitobito_youth and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_youth.

class Event::ParticipationContactData
  attr_reader :person

  class_attribute :mandatory_contact_attrs,
    :contact_attrs,
    :contact_associations

  self.mandatory_contact_attrs = [:email, :first_name, :last_name]

  self.contact_attrs = [:first_name, :last_name, :nickname, :email,
    :address_care_of, :street, :housenumber, :zip_code, :town,
    :country, :gender, :birthday]
  self.contact_associations = []

end
