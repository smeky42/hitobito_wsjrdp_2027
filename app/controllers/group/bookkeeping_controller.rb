# frozen_string_literal: true

#  Copyright (c) 2026, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

# The Buchhaltung sub-tab of a group's Finanzen tab. The action is :show, not
# :index: the core swaps an index action's sheet for its parent sheet, which
# would drop the sub-tabs (doc/navigation.md).
class Group::BookkeepingController < ApplicationController
  before_action :authorize_action
  prepend_before_action :group

  decorates :group

  def show
    render :show
  end

  private

  def authorize_action
    authorize!(:show_finance, group)
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
