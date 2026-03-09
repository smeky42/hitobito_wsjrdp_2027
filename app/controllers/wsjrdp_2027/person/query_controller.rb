# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::Person::QueryController
  extend ActiveSupport::Concern
  included do
    # Add :zero_padded_id to the search columns.
    self.search_columns.push(:zero_padded_id)   # rubocop:disable Style/RedundantSelf

    # Allow querying only people where user has edit permissions.
    # To prevent leaking data in event invitation fields.
    def index
      people = []
      if search_param.size >= 3
        people = list_entries.limit(limit)
        people = decorate(people)
      end

      people.select! { |p| can?(:edit, p) }
      render json: people.collect { |p| p.public_send(serializer) }
    end
  end
end
