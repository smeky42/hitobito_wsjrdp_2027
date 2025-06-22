# frozen_string_literal: true

module ContractHelper
  extend ActiveSupport::Concern

  included do
    # rubocop:disable Metrics/MethodLength
    def payment_array
      [
        ["Rolle","Gesamtbeitrag","Dez 2025 (Anzahlung)","Jan 2026","Feb 2026","Mär 2026","Aug 2026","Nov 2026","Feb 2027","Mai 2027"],
        ["RegularPayer::Group::Unit::Member","3400","300","500","500","500","400","400","400","400"],
        ["RegularPayer::Group::Unit::Leader","2400","150","350","350","350","300","300","300","300"],
        ["RegularPayer::Group::Ist::Member","2600","200","400","400","400","300","300","300","300"],
        ["RegularPayer::Group::Root::Member","1600","50","250","250","250","200","200","200","200"],
        ["EarlyPayer::Group::Unit::Member","3400","","","","","","","",""],
        ["EarlyPayer::Group::Unit::Leader","2400","","","","","","","",""],
        ["EarlyPayer::Group::Ist::Member","2600","","","","","","","",""],
        ["EarlyPayer::Group::Root::Member","1600","","","","","","","",""]
      ]
    end
    # rubocop:enable Metrics/MethodLength

    # each person has a primary group which defines the price and role type
    def role_type(person) 
      roles = person.current_roles_grouped
      # If no role could be detected, fallback should be Youth Participant
      role = "Group::Unit::Member"

      # Last assigned role_type in primary group 
      roles.each do |key, value|
        value.each do |item|
          if item.group_id == person.primary_group_id
            role = item.type
          end
        end
      end
      role 
    end

    def role_full_name(role)
      I18n.t("people.print.contract_roles.#{role.gsub("::", ".")}")
    end

    def payment_role_full_name(role)
      role_full_name(role.split("::", 2)[1])
    end

    def person_payment_role_full_name(person)
      role = payment_role(person)
      role_full_name(role.split("::", 2)[1])
    end

    def payment_role(person)
      role = role_type(person)
      payment_role_name = "RegularPayer"

      if(person.early_payer)
        payment_role_name = "EarlyPayer"
      end

      if((role == "Group::Unit::UnapprovedLeader") or (role == "Group::Unit::Leader"))
        payment_role_name += "::Group::Unit::Leader"
      elsif(role == "Group::Unit::Member")
        payment_role_name += "::Group::Unit::Member"
      elsif(role == "Group::Ist::Member") 
        payment_role_name += "Group::Ist::Member"
      else
        payment_role_name += "Group::Root::Member"
      end
      payment_role_name      
    end
    
    def payment_array_by(person)
      role = person.payment_role
      payment_array.find { |row| row[0] == role }
    end

    def payment_value(person)
      payment_array_by(person)[1]
    end

    def payment_array_table(person)
      array = payment_array_by(person)

      
      array.each_with_index do |element, index|
        if index == 0
          array[index] = role_full_name(array[0].split("::", 2)[1])
        else
          if not array[index].blank?
            array[index] = "#{array[index]} €"
          end
        end
      end     

      [payment_array[0], array]
    end
  
 
  end
end
