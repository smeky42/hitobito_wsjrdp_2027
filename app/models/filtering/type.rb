# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # A value kind: the LIBRARY of operator implementations for it + the UI
  # control to render + how operands are cast. Attributes pick from this
  # library explicitly (operators: %i[...]); nothing is offered by default.
  class Type
    attr_reader :key, :control, :operators

    def initialize(key:, control:, operators:)
      @key = key
      @control = control
      @operators = operators.index_by(&:key)
    end

    def operator(key)
      @operators.fetch(key) # raises on unknown key (declaration-time check)
    end

    # Cast one raw wire operand to the type's Ruby value. Returns nil for an
    # uncastable value -- the compiler then drops the whole condition (neutral).
    def cast(value)
      case key
      when :decimal
        begin  # rubocop:disable Lint/SuppressedExceptionInNumberConversion
          BigDecimal(value.to_s.strip.tr(",", "."))
        rescue ArgumentError, TypeError
          nil
        end
      when :date
        begin
          Date.iso8601(value.to_s.strip)
        rescue ArgumentError, TypeError
          nil
        end
      else
        value.to_s
      end
    end
  end
end
