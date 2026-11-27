# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The pages of the Zahlungsverkehr area (doc/fin/payments.md): who sees them
# and what a save changes.
describe "Zahlungsverkehr" do
  include_context "payment area"

  let_it_be(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let_it_be(:auditor) do
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
      group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
  end

  # The manage tier holds once the session picks it, not by default.
  def sign_in_manage_tier
    sign_in(manager)
    session[:max_finance_permission] = "finance_manage"
  end

  describe Fin::PaymentsController do
    it "gives the write tier the person-level figures" do
      sign_in(accountant)
      get :index

      expect(assigns(:overview)).to be_person_level
    end

    it "leaves them out for the read tier" do
      sign_in(reader)
      get :index

      expect(assigns(:overview)).not_to be_person_level
    end

    context "with views" do
      render_views

      it "offers the read tier no tab of the debits" do
        sign_in(reader)
        get :index

        expect(Capybara.string(response.body)).to have_no_link(href: direct_debits_path)
      end
    end
  end

  describe Fin::PaymentOrdersController do
    before { sign_in(accountant) }

    def listed = controller.send(:payment_orders).page.map(&:id)

    it "filters the orders on their kind" do
      get :index, params: {f: "!(!(!(kd,in,'credit_transfer')))"}

      expect(listed).to eq([transfer_order.id])
    end

    it "filters the orders on their account" do
      get :index, params: {f: "!(!(!(acc,in,'#{account.id}')))"}

      expect(listed).to eq([debit_order.id])
    end

    it "shows a direct debit order with its Sammler and its debits" do
      get :show, params: {id: debit_order.id}

      expect(assigns(:order).id).to eq(debit_order.id)
      expect(assigns(:infos)).to eq([payment_info])
      expect(controller.send(:section_debits?)).to be(true)
    end

    it "shows no debits for a credit transfer" do
      get :show, params: {id: transfer_order.id}

      expect(controller.send(:section_debits?)).to be(false)
    end

    it "shows the read tier an order without its debits" do
      sign_in(reader)
      get :show, params: {id: debit_order.id}

      expect(response).to have_http_status(:ok)
      expect(controller.send(:section_debits?)).to be(false)
    end

    it "answers a list row's frame with the embedded detail" do
      request.headers["Turbo-Frame"] = "po-#{debit_order.id}"
      get :show, params: {id: debit_order.id}

      expect(assigns(:ctx)).to be_embedded
    end
  end

  describe Fin::DirectDebitPaymentInfosController do
    it "shows a Sammler with its debits to the write tier" do
      sign_in(accountant)
      get :show, params: {id: payment_info.id}

      expect(assigns(:info).id).to eq(payment_info.id)
      expect(controller.send(:section_debits?)).to be(true)
    end

    it "shows the read tier a Sammler without its debits" do
      sign_in(reader)
      get :show, params: {id: payment_info.id}

      expect(response).to have_http_status(:ok)
      expect(controller.send(:section_debits?)).to be(false)
    end
  end

  describe Fin::DirectDebitsController do
    let(:params) { {id: returned_debit.id, wsjrdp_direct_debit_pre_notification: changes} }
    let(:changes) { {comment: "Rückruf vereinbart"} }

    it "is closed to the read tier" do
      sign_in(reader)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    it "lets the audit tier read a debit" do
      sign_in(auditor)
      get :show, params: {id: returned_debit.id}

      expect(assigns(:debit).id).to eq(returned_debit.id)
    end

    it "refuses the audit tier the edit page and the save" do
      sign_in(auditor)

      expect { get :edit, params: {id: returned_debit.id} }.to raise_error(CanCan::AccessDenied)
      expect { patch :update, params: params }.to raise_error(CanCan::AccessDenied)
    end

    context "with views" do
      render_views

      it "offers the audit tier no way to edit" do
        sign_in(auditor)
        get :show, params: {id: returned_debit.id}

        expect(Capybara.string(response.body)).to have_no_link(href: edit_direct_debit_path(returned_debit))
      end
    end

    context "for the write tier" do
      before { sign_in(accountant) }

      context "of a debit in a SEPA file" do
        let(:changes) { {comment: "Rückruf vereinbart", amount_eur: "1,00", description: "anders"} }

        it "changes the comment only and goes to the reading page" do
          patch :update, params: params

          expect(response).to redirect_to(direct_debit_path(returned_debit))
          expect(returned_debit.reload).to have_attributes(comment: "Rückruf vereinbart", amount_cents: 20_000,
            description: "Beitrag")
        end
      end

      context "of a debit only announced" do
        before { returned_debit.update!(payment_status: "pre_notified") }

        let(:changes) do
          {amount_eur: "1.234,50", mandate_id: "wsjrdp-neu", mandate_date: "09.10.2025", try_skip: "1",
           comment: "neu", payment_status: "skipped"}
        end

        it "changes its payment data, not its status, and stays on the edit page" do
          patch :update, params: params.merge(stay: "1")

          expect(response).to redirect_to(edit_direct_debit_path(returned_debit))
          expect(returned_debit.reload).to have_attributes(amount_cents: 123_450, mandate_id: "wsjrdp-neu",
            mandate_date: Date.new(2025, 10, 9), try_skip: true, comment: "neu", payment_status: "pre_notified")
        end
      end

      context "sent from another page with a return_url" do
        let(:origin) { "/fin/fees?f=x" }

        it "leads back there from the reading page" do
          get :show, params: {id: returned_debit.id, return_url: origin}

          expect(controller.send(:return_path)).to eq(origin)
        end

        it "returns there on save" do
          patch :update, params: params.merge(return_url: origin)

          expect(response).to redirect_to(origin)
        end

        it "keeps it on the edit page after a save that stays" do
          patch :update, params: params.merge(return_url: origin, stay: "1")

          expect(response).to redirect_to(edit_direct_debit_path(returned_debit, return_url: origin))
        end

        it "ignores a return_url that is no path of this application" do
          %w[https://example.com/x //example.com/x javascript:alert(1)].each do |url|
            patch :update, params: params.merge(return_url: url)

            expect(response).to redirect_to(direct_debit_path(returned_debit)), url
          end
        end
      end
    end

    context "for the manage tier" do
      let(:changes) { {payment_status: "skipped", mandate_id: "wsjrdp-neu"} }

      it "also changes the status of a debit only announced" do
        returned_debit.update!(payment_status: "pre_notified")
        sign_in_manage_tier
        patch :update, params: params

        expect(returned_debit.reload).to have_attributes(payment_status: "skipped", mandate_id: "wsjrdp-neu")
      end

      it "changes the status, but not the mandate reference, once the debit is in a SEPA file" do
        sign_in_manage_tier
        patch :update, params: params

        expect(returned_debit.reload).to have_attributes(payment_status: "skipped", mandate_id: nil)
      end

      it "leaves the status to a session that picked the manage tier" do
        returned_debit.update!(payment_status: "pre_notified")
        sign_in(manager)
        patch :update, params: params

        expect(returned_debit.reload).to have_attributes(payment_status: "pre_notified", mandate_id: "wsjrdp-neu")
      end
    end
  end

  describe Fin::PaymentReturnsController do
    let(:transfer) { returned_transfer(cdtr_iban: "BE79967040785533", value_date: Date.new(2026, 5, 6)) }

    def sent_transfer
      camt_return(-150, bank_transaction_code: "PMNT+ICDT+ESCT", return_reason: nil, endtoend_id: nil,
        cdtr_iban: "BE79967040785533", value_date: Date.new(2026, 4, 28), description: "Überweisung")
    end

    it "is closed to the read tier" do
      sign_in(reader)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    context "for the write tier" do
      before { sign_in(accountant) }

      it "shows an other return as well as a returned direct debit" do
        get :show, params: {id: transfer.id}

        expect(assigns(:return).id).to eq(transfer.id)
      end

      it "saves the status and the comment, nothing else" do
        changes = {return_status: "paid", comment: "Neu angewiesen", description: "nicht erlaubt"}
        patch :update, params: {id: transfer.id, wsjrdp_camt_transaction: changes}

        expect(response).to redirect_to(payment_return_path(transfer))
        expect(transfer.reload).to have_attributes(return_status: "paid", comment: "Neu angewiesen",
          description: "Retoure")
      end

      it "refuses a status there is none of" do
        patch :update, params: {id: transfer.id, wsjrdp_camt_transaction: {return_status: "bogus"}, stay: "1"}

        expect(response).to have_http_status(422)
        expect(transfer.reload.return_status).not_to eq("bogus")
      end

      it "links the chosen original" do
        sent = sent_transfer
        patch :update, params: {id: transfer.id, wsjrdp_camt_transaction: {comment: "x", reverses_id: sent.id}}

        expect(transfer.reload).to have_attributes(reverses_id: sent.id, comment: "x")
      end

      it "saves nothing for an original that is no candidate" do
        other = camt_return(-120, bank_transaction_code: "PMNT+ICDT+ESCT", return_reason: nil, endtoend_id: nil,
          value_date: Date.new(2026, 4, 28))
        patch :update, params: {id: transfer.id, wsjrdp_camt_transaction: {comment: "x"}, original_id_other: other.id}

        expect(response).to have_http_status(422)
        expect(transfer.reload).to have_attributes(reverses_id: nil, comment: "")
      end

      it "unlinks the original on a blank choice" do
        Fin::ReturnOriginals.link!(transfer, sent_transfer)
        patch :update, params: {id: transfer.id, wsjrdp_camt_transaction: {reverses_id: ""}}

        expect(transfer.reload.reverses_id).to be_nil
      end

      it "comes back to the list row after a save inside it" do
        request.headers["Turbo-Frame"] = "bkframe-pr-#{returned.id}"
        patch :update, params: {id: returned.id, stay: "1",
                                wsjrdp_camt_transaction: {return_status: "planned", comment: "Rückruf"}}

        expect(response).to redirect_to(payment_return_path(returned))
        expect(returned.reload).to have_attributes(return_status: "planned", comment: "Rückruf")
      end
    end
  end

  # A debit under its person (/fin/pn).
  describe Fin::WsjrdpDirectDebitPreNotificationsController do
    let(:params) { {id: returned_debit.id, wsjrdp_direct_debit_pre_notification: {comment: "Rückruf vereinbart"}} }

    context "for the write tier" do
      before { sign_in(accountant) }

      it "shows the debit under its person" do
        get :show, params: {id: returned_debit.id}

        expect(assigns(:person)).to eq(person)
      end

      it "saves and returns to the page under the person" do
        patch :update, params: params

        expect(response).to redirect_to(wsjrdp_direct_debit_pre_notification_path(returned_debit))
        expect(returned_debit.reload.comment).to eq("Rückruf vereinbart")
      end

      it "returns to the person's fee page it was opened from" do
        fee_page = "/people/#{person.id}/fee"
        patch :update, params: params.merge(return_url: fee_page)

        expect(response).to redirect_to(fee_page)
      end

      context "of a debit without a person" do
        before { returned_debit.update_columns(subject_type: nil, subject_id: nil) }

        it "sends the reading page to the area's" do
          get :show, params: {id: returned_debit.id}

          expect(response).to redirect_to(direct_debit_path(returned_debit))
        end

        it "sends the edit page to the area's" do
          get :edit, params: {id: returned_debit.id}

          expect(response).to redirect_to(edit_direct_debit_path(returned_debit))
        end
      end
    end

    it "lets the audit tier read, but not save" do
      sign_in(auditor)
      get :show, params: {id: returned_debit.id}

      expect(response).to have_http_status(:ok)
      expect { patch :update, params: params }.to raise_error(CanCan::AccessDenied)
    end

    context "for a unit's leader without finance rights, who may :log the unit's people" do
      before { sign_in(people(:um_a_1)) }

      it "is closed for reading" do
        expect { get :show, params: {id: returned_debit.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "is closed for saving" do
        expect { patch :update, params: params }.to raise_error(CanCan::AccessDenied)
        expect(returned_debit.reload.comment).not_to eq("Rückruf vereinbart")
      end
    end
  end
end
