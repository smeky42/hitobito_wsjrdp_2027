# Roles and permissions

This document covers the hitobito roles defined in this wagon,
hitobito's permission system (permissions → abilities), and the
wagon's `:log` convention.

Unlinked paths (e.g. `app/models/role/types.rb`) are in the hitobito
core, checked out as the sibling directory `../hitobito` in the dev
setup (see [`README.md`](../README.md)).

## The wagon's group and role types

The hitobito core ships **no** group or role types — the
organizational structure is always defined by the wagon, ours in
[`app/models/group/`](../app/models/group/):

| File | Group type | Label (de) | Layer? | Allowed children |
|---|---|---|---|---|
| [`root.rb`](../app/models/group/root.rb) | `Group::Root` | CMT | yes | Unit, Ist, Extern, Root |
| [`unit.rb`](../app/models/group/unit.rb) | `Group::Unit` | Unit | yes | — |
| [`ist.rb`](../app/models/group/ist.rb) | `Group::Ist` | IST | yes | Ist |
| [`extern.rb`](../app/models/group/extern.rb) | `Group::Extern` | Extern | yes | — |

All four types are layers (`self.layer = true`), so each forms its own
permission domain. Roles are nested classes inside their group type
and carry their `permissions` as a class attribute. The German UI
labels live in
[`config/locales/wsjrdp_2027.de.yml`](../config/locales/wsjrdp_2027.de.yml)
(`activerecord.models.group/...`).

### Roles and their permissions

**`Group::Root` (CMT):**

| Role | Label (de) | Permissions |
|---|---|---|
| `Group::Root::Admin` | Admin | `layer_and_below_full`, `admin`, `finance` |
| `Group::Root::Leader` | Leader | `layer_and_below_full` |
| `Group::Root::Finance` | Finance | `layer_and_below_full`, `finance` |
| `Group::Root::Member` | CMT | — |

**`Group::Unit` (Unit):**

| Role | Label (de) | Permissions |
|---|---|---|
| `Group::Unit::Manager` | Unit Manager | `layer_and_below_full` |
| `Group::Unit::Leader` | Unit Leader | `group_full` |
| `Group::Unit::UnapprovedLeader` | Unit Leader (unbestätigt) | — |
| `Group::Unit::Member` | Youth Participant | — |

**`Group::Ist` (IST):**

| Role | Label (de) | Permissions |
|---|---|---|
| `Group::Ist::Leader` | IST Manager (MIST) | `layer_and_below_full` |
| `Group::Ist::Member` | IST | — |

**`Group::Extern` (Extern):**

| Role | Label (de) | Permissions |
|---|---|---|
| `Group::Extern::Member` | Extern | — |

Key point: `layer_and_below_full` is always **relative to the layer
the role sits in**. A `Group::Root::Leader` holds it on the root layer
(and thus everything below), a `Group::Unit::Manager` only on their
unit layer, a `Group::Ist::Leader` only on the IST layer.

## The hitobito permission system

Two stages: static **permissions** on the role, and dynamic
**abilities** (CanCanCan) mapping permissions to concrete actions and
subjects.

### Group vs. layer

A layer is not a model of its own — every layer *is* a group. A group
type declares `self.layer = true` (default `false`, `Group::Types`).
All groups form one tree (nested set), and every group stores
`layer_group_id`: the id of the closest layer group up the tree,
itself included (`Group::Types#set_layer_group_id`). A layer therefore
consists of one layer group plus all non-layer subgroups down to the
next layer group — a nested layer group starts a **new** permission
domain. `group_*` permissions act on the single group (`*_and_below`:
its subtree, ignoring layer boundaries), `layer_*` permissions on the
whole layer, `layer_and_below_*` additionally on all layers beneath.
Person visibility from above (`visible_from_above`) and the
superior-only group attributes follow the same layer boundaries.

In this wagon every group type is a layer, so each group is its own
permission domain. The actual tree (dev DB, synced with production) is
almost flat: the root group holds all units (A/B/D/E/K series, T1,
plus registration and waiting-list units), the `Group::Ist` groups
"IST Registration", "IST Warteliste" and **BMT**, two `Group::Extern`
groups, and "CMT Warteliste" (a nested `Group::Root`). The only nested
subtree is under "IST Registration": the regional `Group::Ist` groups
IST Süd, IST Süd West, IST West and IST Nord Ost — each again its own
layer. Derived scopes:

- A **Unit Leader** (`group_full`) acts on exactly their one unit
  group; units have no subgroups, so group = layer = one group.
- A **MIST** (`Group::Ist::Leader`, `layer_and_below_full`) acts on
  their own IST group plus all Ist groups nested beneath it: in "IST
  Registration" that includes the four regional groups; in a regional
  group, in "IST Warteliste" or in BMT it is just that one group. BMT
  is a *sibling* of the IST groups, so BMT and IST domains are fully
  disjoint — only root-layer (CMT) roles span both.
- Root-layer roles reach every layer below the root group, including
  "CMT Warteliste". The reverse does not hold: a role *inside* "CMT
  Warteliste" holds its permissions on that nested layer only — it is
  not "on the root layer" for constraints like
  `if_layer_and_below_full_on_root`.

### Permissions

The full set is defined in core `app/models/role/types.rb`
(`Role::Types::Permissions`):

`admin`, `layer_and_below_full`, `layer_and_below_read`, `layer_full`,
`layer_read`, `group_and_below_full`, `group_and_below_read`, `group_full`,
`group_read`, `contact_data`, `approve_applications`, `finance`,
`impersonation`, `see_invisible_from_above`

`PermissionImplications`: each `*_full` permission implies its `*_read`
counterpart. `layer_*` permissions act on the layer of the group holding the
role; `group_*` permissions on the group itself (`*_and_below` variants
include subgroups).

### Abilities (CanCanCan + AbilityDsl)

What a permission concretely *allows* is defined in the core ability
classes under `app/abilities/` (e.g. `event_ability.rb`,
`person_ability.rb`, `group_ability.rb`) using hitobito's own DSL
(`AbilityDsl::Base`):

```ruby
on(Event) do
  permission(:layer_full).may(:update, :create, :destroy).in_same_layer_if_active
end
```

- `on(Subject)` — which model class the rules apply to.
- `permission(:x).may(:action)` — which permission allows which action
  (`:any` = any logged-in person; `class_side(...)` for class-level
  actions like `index`).
- The final call (`in_same_layer_if_active`, `herself`, `if_admin`, …)
  is a **constraint**: a method on the ability class, evaluated at
  runtime against user and subject. Shared constraints live in
  `app/abilities/ability_dsl/constraints/`; `if_admin` and
  `nobody`/`everybody` in `app/abilities/ability_dsl/base.rb`.
- All rules land in the `AbilityDsl::Store`, keyed by the triple
  **(permission, subject class, action)**. `can?(action, subject)` is
  true as soon as *any* config for one of the user's permissions
  matches.

### Wagon overrides

The wagon hooks into the core abilities via concerns
([`lib/hitobito_wsjrdp_2027/wagon.rb`](../lib/hitobito_wsjrdp_2027/wagon.rb),
e.g. `EventAbility.include Wsjrdp2027::EventAbility`). Wagon blocks
run **after** the core blocks, and the store **overwrites** configs
with the same key (permission, subject, action). This lets the wagon

- revoke core rules: `permission(:group_full).may(:log, …).nobody` in
  [`person_ability.rb`](../app/abilities/wsjrdp_2027/person_ability.rb)
  and `.none` in
  [`group_ability.rb`](../app/abilities/wsjrdp_2027/group_ability.rb),
- add new rules: the `:log` grant on `Event` in
  [`event_ability.rb`](../app/abilities/wsjrdp_2027/event_ability.rb),
  the `fin_admin` grants in
  [`various_ability.rb`](../app/abilities/wsjrdp_2027/various_ability.rb).

All wagon ability files live under
[`app/abilities/wsjrdp_2027/`](../app/abilities/wsjrdp_2027/).

### Where is this documented?

In the core repo (locally `../hitobito/doc/`, on GitHub
<https://github.com/hitobito/hitobito/tree/master/doc>):

- `doc/architecture/08_konzepte.md` — group/role-type metamodel,
  layers, annotated group-type example ("Group- and Roletypes"
  section).
- `doc/architecture/gems/cancancan.md` — CanCanCan basics (`can?`,
  `authorize!`, `accessible_by`).
- `doc/developer/roles/README.md` — roles; active/ended/future roles.
- `doc/developer/roles/basic_permission_roles.md` — roles with
  `basic_permissions_only` (heavily restricted view).
- Example wagon with a generic structure:
  <https://github.com/hitobito/hitobito_generic>

The wagon also has a guard spec:
[`spec/support/shared_event_ability_examples.rb`](../spec/support/shared_event_ability_examples.rb)
asserts that the `EVENT_ACTIONS` constant exactly matches all actions
configured for `Event` in the ability store, and its shared examples
"only allow event actions" check the allowed **and** the forbidden
list per role (used in
[`spec/abilities/event_ability_spec.rb`](../spec/abilities/event_ability_spec.rb)).

## The `:log` convention in `hitobito_wsjrdp_2027`

In core, `:log` is the **change-log** action (PaperTrail): the log tab
of groups (`group/log#index`) and people
(`person/log#index`). Accordingly, core grants `:log` only to the
full-access permissions (`layer_full`, `layer_and_below_full`,
`group_full`, `group_and_below_full`).

Beyond that, `hitobito_wsjrdp_2027` uses `can?(:log, subject)` as a
generic gate for a **"privileged/internal view of this
subject"**. Examples:

- internal person/group fields:
  [`app/views/people/_attrs.html.haml`](../app/views/people/_attrs.html.haml),
  [`app/views/groups/_fields_wsjrdp_2027.html.haml`](../app/views/groups/_fields_wsjrdp_2027.html.haml),
  [`app/views/contactable/_fields.html.haml`](../app/views/contactable/_fields.html.haml)
- person tags, uploads, fee data:
  [`app/views/person/tags/_tag.html.haml`](../app/views/person/tags/_tag.html.haml),
  [`app/controllers/person/upload_controller.rb`](../app/controllers/person/upload_controller.rb),
  [`app/controllers/person/fee_controller.rb`](../app/controllers/person/fee_controller.rb)
- navigation: the Contingent main menu item only shows for `can?(:log,
  Group.root)`
  ([`app/helpers/wsjrdp_2027/navigation_helper.rb`](../app/helpers/wsjrdp_2027/navigation_helper.rb))
- finance models: `permission(:finance).may(:fin_admin, …, :log,
  …).if_finance_on_root` in
  [`various_ability.rb`](../app/abilities/wsjrdp_2027/various_ability.rb)

Who may `:log` what (core grants plus wagon overrides):

| Subject | may `:log` | effectively in this wagon |
|---|---|---|
| `Person` | `layer_full` / `layer_and_below_full` in the person's layer; wagon revokes `:any` (herself) and `group_full` | CMT Admin/Leader/Finance (everywhere), Unit Manager (own unit), IST Manager (IST layer) — **not** Unit Leader |
| `Group` | as core, but wagon revokes `group_full` | `can?(:log, Group.root)` ⇒ only CMT roles with `layer_and_below_full` |
| finance models (`AccountingEntry`, …) | `finance` on the root layer | Root::Admin, Root::Finance |
| `Event` | `layer_and_below_full` on the root layer (the grant below) | CMT Admin/Leader/Finance |

The root superuser (`can :manage, :all`, see core `ability.rb`) may
always do everything regardless.

## Example: Effect of the `:log` grant on `Event`

[`app/abilities/wsjrdp_2027/event_ability.rb`](../app/abilities/wsjrdp_2027/event_ability.rb)
adds:

```ruby
permission(:layer_and_below_full).may(:log).if_layer_and_below_full_on_root
```

Before, `Event` had **no** `:log` config at all — `can?(:log, event)` was
`false` for every regular user. Now:

- **Who:** `if_layer_and_below_full_on_root` (core `event_ability.rb`)
  checks for `layer_and_below_full` **on the root layer** ⇒
  `Group::Root::Admin`, `Group::Root::Leader`,
  `Group::Root::Finance`. Unit Managers and IST Managers hold
  `layer_and_below_full` on their own unit/IST layer and are therefore
  **excluded**. (A separate grant via the `admin` permission would be
  redundant: the only role with `admin` is `Group::Root::Admin`, which
  holds `layer_and_below_full` on the root layer anyway.)
- **On what:** the constraint only checks the user, not the event —
  the grant applies to **every** event, whatever layer it belongs to.
- **Visible effect:** there is no event log tab or route (as of core
  2.5.7); `:log` on `Event` is purely the gate convention from
  section 3. It is consumed by the wagon's event-form overrides, which
  hide the "advanced" fields behind `if can?(:log, entry)`:
  - [`app/views/events/_additional_fields.html.haml`](../app/views/events/_additional_fields.html.haml):
    `globally_visible`
  - [`app/views/events/_application_fields.html.haml`](../app/views/events/_application_fields.html.haml):
    `external_applications`, `participations_visible`, `priorization`,
    `automatic_assignment`, `waiting_list`, `requires_approval`, `signature`,
    `signature_confirmation` (+ text), `applications_cancelable`,
    `display_booking_info` (each only where the event type uses the attribute)

  Without the grant these fields were hidden from **everyone** (except
  the root superuser); with it, CMT Admin/Leader/Finance can see and
  edit them again.
- **Specs:** the guard spec "EVENT_ACTIONS has complete list of
  actions"
  ([`spec/support/shared_event_ability_examples.rb`](../spec/support/shared_event_ability_examples.rb))
  requires `:log` in `EVENT_ACTIONS`. In
  [`spec/abilities/event_ability_spec.rb`](../spec/abilities/event_ability_spec.rb)
  the "CMT leader" context covers the grant positively (`:log` in the
  `allowed:` list, for unit and IST events). The "unit manager" and
  "IST leader (MIST)" contexts guard the constraint: both roles hold
  `layer_and_below_full` on their own layer and may do almost
  everything with their own layer's events — but `:log` stays in the
  forbidden list. For all other roles `:log` lands in the shared
  examples' negative check automatically.
