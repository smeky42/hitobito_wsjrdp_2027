# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A THROWAWAY host for declarations that are meant to be WRONG (see the last
# describe below). It subclasses a real controller, so the tables go through the
# real declaration macro, and it lives here rather than under app/controllers, so
# the smoke below never resolves it; the class_attribute writer stays on this
# subclass, so the parent's own tables are untouched.
class BadPresetGroupController < Fin::WsjrdpFinAccountsController
  # One quick-select GROUP on the wallet's "Art", correct except for what the
  # caller overrides.
  def self.kind_group_policy(prefix, **wrong)
    wsjrdp_expandable_table_policy prefix: prefix,
      filter: {schema: Fin::MossWalletFilterSchema,
               presets: [{group: "kind", attribute: "kind", operator: "in",
                          members: [{key: "card", label: "Karte",
                                     value: Fin::MossTransactionsFilterSchema::KINDS.first}]}
                 .merge(wrong)]}
  end

  # The members of a group share ONE `attribute in (values)` slot.
  WRONG_OPERATOR_POLICY = kind_group_policy("bpgo", operator: "not_in")
  # A member may only name a value the attribute itself offers.
  WRONG_VALUE_POLICY = kind_group_policy("bpgv",
    members: [{key: "card", label: "Karte", value: "MossNoSuchKind"}])
end

# THE smoke test of every expandable-table declaration in the wagon: resolve each
# declared policy once, with empty params, on a request-less controller instance.
#
# Why this exists (doc/plans/2026-09_expandable-table-state.md, D8.10): a table's
# fixed filter slots are parsed STRICTLY at resolve time, so a typo in a pinned
# condition -- or an attribute later removed from the schema -- raises instead of
# being dropped by the neutral-on-invalid compiler, which would silently WIDEN
# the page's scope. Without a spec that touches every declaration, that raise
# would first happen in production. It also catches a filter option declared
# without its schema:, an unknown field, a bad column token and a store_key lambda
# that no longer resolves.
describe "expandable table policies" do
  # Every controller of THIS wagon that declares at least one table.
  def self.stateful_controllers
    root = File.expand_path("../../../app/controllers", __dir__)
    Dir[File.join(root, "**", "*_controller.rb")].sort.filter_map { |path|
      klass = path.delete_prefix("#{root}/").delete_suffix(".rb").camelize.safe_constantize
      next unless klass.is_a?(Class) && klass.respond_to?(:wsjrdp_expandable_table_policies)

      klass if klass.wsjrdp_expandable_table_policies.any?
    }
  end

  it "finds the declaring controllers at all (guards the guard)" do
    expect(self.class.stateful_controllers).to include(Fin::BookingsController,
      Fin::ReconciliationController, Fin::MossTransactionsController)
  end

  stateful_controllers.each do |controller_class|
    describe controller_class do
      # No dispatch, no authorization, no rendering -- only what the resolver
      # needs: params, the session and the cookie jar.
      let(:controller) do
        controller_class.new.tap do |instance|
          request = ActionDispatch::TestRequest.create
          instance.set_request!(request)
          instance.set_response!(ActionDispatch::TestResponse.new)
        end
      end

      controller_class.wsjrdp_expandable_table_policies.each do |prefix, policy|
        it "resolves the #{prefix.presence || "(unprefixed)"} table" do
          state = controller.wsjrdp_expandable_table_state(policy)
          expect(state).to be_frozen
          expect(state.prefix).to eq(prefix)
          # Touching the filter proves its schemas bound and its fixed slots
          # passed Wsjrdp::Filtering::FilterSchema#parse_fixed!.
          expect(state.filter.effective_slots).to be_an(Array)
        end
      end

      # The declaration RETURNS the policy and the resolution takes that object,
      # so a table is addressed once, by identity -- there is no prefix string to
      # mistype and no way to reach another controller's table.
      it "refuses a policy that is not declared on it" do
        foreign = Wsjrdp::TableStatePolicy.new(prefix: "zz")
        expect { controller.wsjrdp_expandable_table_state(foreign) }
          .to raise_error(ArgumentError, /not a table declared on #{controller_class.name}/)
      end
    end
  end

  # The other host-authored half of a filter declaration: the quick-select
  # presets. A GROUP of buttons shares ONE `attribute in (values)` slot and is
  # parsed as strictly as a fixed slot -- another operator, an attribute that
  # does not offer `in`, a value outside the attribute's options or an unknown
  # key raises, naming the GROUP so the message says which declaration to fix.
  # The smoke above already resolves the wallet's own group; these two show what
  # it would report.
  describe "a wrongly declared filter preset group" do
    let(:controller) do
      BadPresetGroupController.new.tap do |instance|
        instance.set_request!(ActionDispatch::TestRequest.create)
        instance.set_response!(ActionDispatch::TestResponse.new)
      end
    end

    it "refuses an operator the members cannot share" do
      expect { controller.wsjrdp_expandable_table_state(BadPresetGroupController::WRONG_OPERATOR_POLICY) }
        .to raise_error(ArgumentError, /filter preset group kind: operator "not_in"/)
    end

    it "refuses a member value the attribute does not offer" do
      expect { controller.wsjrdp_expandable_table_state(BadPresetGroupController::WRONG_VALUE_POLICY) }
        .to raise_error(ArgumentError,
          /filter preset group kind: member card has the value "MossNoSuchKind"/)
    end
  end
end
