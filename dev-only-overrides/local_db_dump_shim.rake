# frozen_string_literal: true

# Dev-only shim, loaded ONLY via the gitignored symlink at lib/tasks/
# (created by dev-only-overrides/create_symlinks.sh).
#
# The `wagons` gem overrides db:_dump (wagons.rake) and, when run through the
# `app:` proxy (`rails app:db:migrate:down` from the wagon), its body references
# the ABSOLUTE task `db:_dump` (Rake::Task[:'db:_dump'].reenable). Under the app:
# namespace only `app:db:_dump` exists, so migrate:down aborts with
# "Don't know how to build task 'db:_dump'". Providing a no-op absolute
# db:_dump / db:_dump_rails makes that lookup resolve. Dumping stays skipped on
# purpose -- db/schema.rb is maintained by hand in this repo.
%w[db:_dump db:_dump_rails].each do |name|
  Rake::Task.define_task(name) {} unless Rake::Task.task_defined?(name)
end
