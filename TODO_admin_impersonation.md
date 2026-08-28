# TODO: Impersonation for CMT admins

Goal (user requirement): CMT admins may impersonate other people; nobody
else may. Currently impersonation only works in dev because of two
uncommitted hacks in the read-only core checkout that allow EVERYBODY to
impersonate. This file collects everything known so we can pick the topic
up later.

## Status

Done (committed):

* Assignment of the admin/finance roles is restricted to CMT admins
  (`Role.admin_only_assignment` + general constraints in
  `Wsjrdp2027::RoleAbility`; commit "Restrict assignment of admin-only
  roles to CMT admins", PR #161). This matters here because whoever can
  hand out the admin role will also hand out the impersonation right.
* The dev login bypass respects the warden session
  (`dev-only-overrides/local_dev_only_login_bypass.rb`, PR #160), so
  impersonation works under the bypass. Before the fix, clicking
  "Imitieren" appeared to impersonate oneself: the old `current_person`
  override ignored the warden session that
  `Person::ImpersonationController#create` had just set.

Open (the actual TODO):

1. Give the admin role the impersonation permission (wagon,
   `app/models/group/root.rb`):

   ```ruby
   class Admin < ::Role
     self.permissions = %i[layer_and_below_full admin finance impersonation]
   end
   ```

   `:impersonation` is an existing core permission
   (`Role::Permissions` in `core app/models/role/types.rb`); the core
   already ships the rule
   `permission(:impersonation).may(:impersonate_user).all`
   (core `app/abilities/person_ability.rb`). No wagon ability code
   needed.
2. Revert the two core hacks (user step -- the core checkout is
   read-only for the agent). Both are currently still present:

   * `app/abilities/person_ability.rb`: added line
     `permission(:any).may(:impersonate_user).all` -- currently lets
     EVERYONE impersonate.
   * `app/helpers/people_helper.rb`: `may_impersonate?` hard-coded to
     `true` -- shows the button everywhere (even on one's own page,
     where the controller then silently refuses).

   ```sh
   git -C ../hitobito checkout app/abilities/person_ability.rb app/helpers/people_helper.rb
   ```
3. Add specs: admin may `:impersonate_user` a person; leader, finance
   and member may not (e.g. extend
   `spec/abilities/finance_ability_spec.rb` or a small person-ability
   spec). Note: fixtures contain no admin role -- fabricate one, as the
   existing specs do.
4. Verify that the three person-ability spec files are green again:
   they currently fail with 34 examples (10+12+12 in
   `ist/unit_leader/youth_participant_person_ability_spec.rb`), all
   with the extra element `:impersonate_user` -- caused by core hack
   (a), not by wagon code.
5. Decide on `Settings.impersonate.notify`: when true and the
   impersonated person has password+email, hitobito mails them about
   the impersonation. Every impersonation is PaperTrail-logged either
   way (events `:impersonate` / `:impersonation_done`).
6. Dev environment follow-up: the login-bypass default person (id 1)
   has NO roles -- after the hack revert it cannot impersonate anymore.
   To test impersonation in dev, set an admin person id in the
   gitignored `config/dev_only_settings.local.yml`
   (`dev_only > login_bypass > current_user_person_id`; dev DB has
   admin roles e.g. on person ids 2, 60, 64) -- or reconsider the
   bypass default.

## How impersonation works (core facts, verified)

* Button: `people/_actions_show.html.haml` -> `may_impersonate?(user,
  group)` (`people_helper.rb`): `can?(:impersonate_user, user) && user
  != current_user && !origin_user && group.people.exists?(id:
  user.id)`.
* `Person::ImpersonationController#create`: guard `person ==
  current_user || origin_user` (silently redirects back -- nested
  impersonation is impossible; end the current one first), then
  `session[:origin_user] = current_user.id`, `sign_in(person)`,
  PaperTrail entry, optional notification mail. `#destroy` signs the
  origin user back in and clears `session[:origin_user]`.
* While impersonating, ALL `can?` checks run on the impersonated
  person; `origin_user` has no influence on abilities. Impersonation is
  therefore a valid tool to verify permission changes (used
  successfully for the admin-only-roles work: impersonated leader ->
  403 on forbidden role actions, impersonated admin -> allowed).
* The "sign out" link becomes "end impersonation" while
  `session[:origin_user]` is set (`layout_helper#sign_out_path`).
* The wagon's `Wsjrdp2027::PersonAbility` does not restrict
  `:impersonate_user` (no `.nobody` on it), so the core rule applies
  unmodified.

## Dev-environment notes

* Ability changes require an app restart: `AbilityDsl::Store` caches
  the whole rule configuration per process (see the dev note in
  `doc/roles.md`).
* The login bypass reads the person from
  `config/dev_only_settings.local.yml` (default person 1) and lets the
  warden session win -- a real sign-in or an impersonation stays
  authoritative.
* Verification recipe (browser or curl): impersonate a leader, try a
  forbidden action (expect 403 / "not authorized" flash), end the
  impersonation, impersonate an admin, repeat (expect success), clean
  up any created records.

## History / related questions from the sessions

* "Wie kann ich sicherstellen, dass nur CMT Admins die CMT Admin Rolle
  vergeben können. CMT Admins sollen andere Personen imitieren dürfen."
  -- role-assignment half is DONE (PR #161), impersonation half is this
  TODO.
* "Imitieren imitiert mich selbst (person-id 65)" -- dev bug, fixed via
  the warden-aware login bypass (PR #160).
* "Wie kann ich die Änderung verifizieren, wenn ich mit imitieren
  arbeite?" -- answered; recipe above. Follow-up finding: the role-type
  dropdown hides admin-only types automatically
  (`GroupDecorator#possible_roles` asks the same constraints).
