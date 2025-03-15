# frozen_string_literal: true

require Rails.root.join('db', 'seeds', 'support', 'person_seeder')

class Wsjrdp2027PersonSeeder < PersonSeeder

  def amount(role_type)
    case role_type.name.demodulize
    when 'Member' then 5
    else 1
    end
  end

end

wsjrdp_devs = [
  'Peter Neubauer',
  'David Fritzsche',
  'Raphael Topel',
  'Felix Maurer',
  'Lukas Schneider'
]

devs = { }

wsjrdp_devs.each do |dev|
  devs[dev] = "#{dev.downcase.gsub(' ', '.')}@worldscoutjamboree.de"
end

seeder = Wsjrdp2027PersonSeeder.new

seeder.seed_all_roles

root = Group.root
devs.each do |name, email|
  seeder.seed_developer(name, email, root, Group::Root::Leader)
end
