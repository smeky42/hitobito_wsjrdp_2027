# frozen_string_literal: true

namespace :app do
  namespace :license do
    task :config do # rubocop:disable Rails/RakeEnvironment
      @licenser = Licenser.new('hitobito_wsjrdp_2027',
        'World Scout Jamoboree 2027 - German Contingent',
        'https://github.com/hitobito/hitobito_wsjrdp_2027')
    end
  end
end
