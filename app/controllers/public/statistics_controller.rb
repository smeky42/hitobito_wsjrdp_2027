# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class Public::StatisticsController < ApplicationController
  skip_before_action :authenticate_person!

  skip_authorization_check
  skip_authorize_resource
  layout false

  include ContractHelper

  def index
    people = Person.where.not(status: ["registered", "deregistration_noted", "deregistered"])

    @ist_count = people.count { |person| ist?(PersonDecorator.new(person)) }
    @yp_count = people.count { |person| yp?(PersonDecorator.new(person)) }
    @ul_count = people.count { |person| ul?(PersonDecorator.new(person)) }
    @cmt_count = people.count { |person| cmt?(PersonDecorator.new(person)) }

    @units_by_yp = (@yp_count / 36.0).floor
    @units_by_ul = (@ul_count / 4.0).floor

    if @units_by_ul < @units_by_yp
      @missing_uls = (@units_by_yp * 4) - @ul_count
      @missing_yps = 0
    elsif @units_by_ul > @units_by_yp
      @missing_yps = (@units_by_ul * 36) - @yp_count
      @missing_uls = 0
    else
      @missing_uls = 0
      @missing_yps = 0
    end
    @max_units = [@units_by_yp, @units_by_ul].max
  end
end
