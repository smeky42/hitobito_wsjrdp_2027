# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Person::SpendController < ApplicationController
  include PersonInPrimaryGroup

  class_attribute :permitted_attrs

  respond_to :html

  before_action :authorize_action

  def show
    render :show
  end

  private

  def authorize_action
    @person ||= person
    @group ||= group
    authorize!(:edit, @person)
  end
end
