# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss tabs Benutzer, Teams and Abteilungen (Fin::MossOrganisationController
# and its three subclasses): what the lists filter and count, what a save
# changes and where it leads, and who may read or edit. How a page looks is
# not checked here. All names and ids are invented.
describe "Moss organisation pages" do
  render_views

  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  let!(:department) { MossDepartment.create!(moss_department_uuid: SecureRandom.uuid, name: "Abteilung Logistik") }
  let!(:team) do
    MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Küche", status: "ACTIVE",
      moss_department_uuid: department.moss_department_uuid)
  end
  let!(:empty_team) { MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Leer", status: "ARCHIVED") }
  let!(:user) do
    MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Erika", last_name: "Beispiel",
      email: "erika.beispiel@example.com", status: "ACTIVE", roles: %w[USER TEAMLEAD],
      moss_team_uuid: team.moss_team_uuid, person: people(:yp_a_1))
  end
  let!(:invited) do
    MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Max", last_name: "Muster",
      email: "max.muster@example.com", status: "INVITED", roles: %w[USER], manager_uuid: user.moss_user_uuid,
      moss_team_uuid: SecureRandom.uuid)
  end

  before { team.update!(team_lead_uuid: user.moss_user_uuid) }

  def doc = Nokogiri::HTML(response.body)

  def row_texts = doc.css("tr.exp-row").map { |tr| tr.text.squish }

  describe Fin::MossUsersController, type: :controller do
    describe "GET index" do
      before { sign_in(accountant) }

      it "filters by status" do
        get :index, params: {f: "!(!(!(st,in,INVITED)))"}

        expect(row_texts).to contain_exactly(include("Max Muster"))
      end

      it "filters by role, any of the chosen" do
        get :index, params: {f: "!(!(!(rl,in,TEAMLEAD)))"}
        expect(row_texts).to contain_exactly(include("Erika Beispiel"))
      end

      it "filters by a missing person link" do
        get :index, params: {f: "!(!(!(pl,in,nein)))"}
        expect(row_texts).to contain_exactly(include("Max Muster"))
      end

      it "filters by team and by name" do
        get :index, params: {f: "!(!(!(tm,in,'#{team.moss_team_uuid}')))"}
        expect(row_texts).to contain_exactly(include("Erika Beispiel"))

        get :index, params: {f: "!(!(!(q,ct,'erika beis')))"}
        expect(row_texts).to contain_exactly(include("Erika Beispiel"))
      end

      it "shows users of other or no status by default, as the counts do, and hides them on request" do
        MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Hanna", last_name: "Versteckt", status: "HIDDEN")
        MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Olaf", last_name: "Ohne", status: nil)
        MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Dora", last_name: "Alt", status: "DEACTIVATED")

        get :index
        expect(row_texts.join(" ")).to include("Hanna Versteckt", "Olaf Ohne")
        expect(row_texts.join(" ")).not_to include("Dora Alt")

        get :index, params: {u: "status.active+invited"}
        expect(row_texts.join(" ")).not_to include("Hanna Versteckt", "Olaf Ohne")
      end

      it "drops a team condition whose value is no uuid instead of failing" do
        get :index, params: {f: "!(!(!(tm,in,'x')))"}

        expect(response).to be_successful
        expect(row_texts).to include(include("Erika Beispiel"))
      end

      it "hands the posted filter on as a GET (PRG)" do
        post :apply, params: {filter_json: [[["status", "in", "ACTIVE"]]].to_json}

        expect(response).to have_http_status(:see_other)
        expect(response.location).to start_with("http://test.host#{moss_users_path}?")
        expect(CGI.unescape(response.location)).to include("st,in,'ACTIVE'")
      end
    end

    describe "GET edit and PATCH update" do
      before { sign_in(accountant) }

      it "saves the comment and the person, nothing else" do
        other = people(:admin)
        patch :update, params: {id: user.id, moss_user: {comment: "Zuständig für Einkauf", person_id: other.id,
                                                         email: "x@example.com", status: "DEACTIVATED"}}

        expect(response).to redirect_to(moss_user_path(user))
        expect(user.reload.comment).to eq("Zuständig für Einkauf")
        expect(user.person).to eq(other)
        expect(user.email).to eq("erika.beispiel@example.com")
        expect(user.status).to eq("ACTIVE")
      end

      it "refuses a person that does not exist" do
        patch :update, params: {id: user.id, moss_user: {person_id: Person.maximum(:id) + 1}}

        expect(response).to have_http_status(:bad_request)
        expect(user.reload.person).to eq(people(:yp_a_1))
      end

      it "answers a save from a row of a table on another page with the detail in that row" do
        request.headers["Turbo-Frame"] = "bkframe-mtu_#{team.id}-#{user.id}"
        patch :update, params: {id: user.id, moss_user: {comment: "Neu"}}

        expect(response).to redirect_to(moss_user_path(user))
      end

      it "takes a return_url only as a path on this site" do
        cancel = -> { doc.css("a").find { |a| a.text.squish == "Abbrechen" }["href"] }

        get :edit, params: {id: user.id, return_url: "javascript:alert(1)"}
        expect(cancel.call).to eq(moss_user_path(user))
        get :edit, params: {id: user.id, return_url: "//evil.example"}
        expect(cancel.call).to eq(moss_user_path(user))
        get :edit, params: {id: user.id, return_url: "/fin/moss/teams"}
        expect(cancel.call).to eq("/fin/moss/teams")
      end

      it "unlinks the person when the field is cleared" do
        patch :update, params: {id: user.id, moss_user: {person_id: ""}}

        expect(user.reload.person).to be_nil
      end

      it "answers a save from a row by reloading the list with the row open" do
        request.headers["Turbo-Frame"] = "bkframe-mu-#{user.id}"
        request.accept = "text/vnd.turbo-stream.html, text/html"
        patch :update, params: {id: user.id, moss_user: {comment: "Neu"}}

        expect(doc.at_css("turbo-stream[action='redirect_top']")["url"])
          .to eq(moss_users_path(Fin::MossUsersController::POLICY.param_name(:open) => user.id))
      end

      it "answers a save from the page's frame by reloading the page" do
        request.headers["Turbo-Frame"] = "bkframe-mupage-#{user.id}"
        request.accept = "text/vnd.turbo-stream.html, text/html"
        patch :update, params: {id: user.id, moss_user: {comment: "Neu"}}

        expect(doc.at_css("turbo-stream[action='redirect_top']")["url"]).to eq(moss_user_path(user))
      end
    end

    it "lets the audit tier read the list and the page, but not edit" do
      sign_in(auditor)

      get :index
      expect(response).to be_successful
      get :show, params: {id: user.id}
      expect(response).to be_successful
      expect { get :edit, params: {id: user.id} }.to raise_error(CanCan::AccessDenied)
      expect { patch :update, params: {id: user.id, moss_user: {comment: "x"}} }
        .to raise_error(CanCan::AccessDenied)
      expect(user.reload.comment).to eq("")
    end

    it "is closed to the read tier" do
      sign_in(reader)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
      expect { get :show, params: {id: user.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "is closed to a person without finance rights" do
      sign_in(people(:yp_a_1))
      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe Fin::MossTeamsController, type: :controller do
    before { sign_in(accountant) }

    it "counts as Benutzer the users in Moss that are not deactivated, linked to a person or not" do
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "DEACTIVATED", moss_team_uuid: team.moss_team_uuid)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "ACTIVE", moss_team_uuid: team.moss_team_uuid,
        moss_removed_at: Time.current)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "INVITED", moss_team_uuid: team.moss_team_uuid)
      get :index

      row = doc.css("tr.exp-row").find { |tr| tr.text.include?("Team Küche") }
      # Erika (with a person) and the invited user (without one).
      expect(row.at_css("td[data-colkey='user_count']").text.squish).to eq("2")
    end

    it "sorts by the user count and filters on it" do
      get :index, params: {s: "uc~"}
      expect(row_texts.first).to include("Team Küche")

      get :index, params: {f: "!(!(!(uc,nz)))"}
      expect(row_texts).to contain_exactly(include("Team Küche"))
    end

    it "shows the active teams by default, the archived ones once chosen" do
      get :index
      expect(row_texts).to contain_exactly(include("Team Küche"))
      pressed = doc.css("a.flt-preset").to_h { |a| [a.text.squish, a["aria-pressed"]] }
      expect(pressed.values_at("Aktiv", "Archiviert")).to eq(%w[true false])

      get :index, params: {u: "status.archived"}
      expect(row_texts).to contain_exactly(include("Team Leer"))
    end

    it "filters by status and department" do
      get :index, params: {u: "status.active+archived+others", f: "!(!(!(st,in,ARCHIVED)))"}
      expect(row_texts).to contain_exactly(include("Team Leer"))

      get :index, params: {f: "!(!(!(dp,in,'#{department.moss_department_uuid}')))"}
      expect(row_texts).to contain_exactly(include("Team Küche"))
    end

    describe "the team's users" do
      let!(:deactivated) do
        MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Dora", last_name: "Alt",
          email: "dora.alt@example.com", status: "DEACTIVATED", roles: %w[USER], moss_team_uuid: team.moss_team_uuid)
      end

      def user_rows = doc.css("tr.exp-row").map { |tr| tr.text.squish }.select { |t| t.match?(/Beispiel|Alt|Muster/) }

      it "leaves deactivated users out by default: Aktiv and Eingeladen pressed" do
        get :show, params: {id: team.id}

        expect(user_rows).to contain_exactly(include("Erika Beispiel"))
        pressed = doc.css("a.flt-preset").to_h { |a| [a.text.squish, a["aria-pressed"]] }
        expect(pressed.values_at("Aktiv", "Eingeladen", "Deaktiviert")).to eq(%w[true true false])
      end

      it "shows them once the quick filter is off" do
        get :show, params: {id: team.id, uu: "status.active+invited+deactivated"}

        expect(user_rows).to contain_exactly(include("Erika Beispiel"), include("Dora Alt"))
      end

      it "hands the posted filter on to the team's page (PRG)" do
        post :apply_users, params: {id: team.id, filter_json: [[["status", "in", "DEACTIVATED"]]].to_json}

        expect(response).to have_http_status(:see_other)
        expect(response.location).to start_with(moss_team_url(team))
        expect(response.location).to include("uf=")
      end
    end

    it "saves the comment only" do
      patch :update, params: {id: team.id, moss_team: {comment: "Notiz", name: "Anders"}}

      expect(team.reload.comment).to eq("Notiz")
      expect(team.name).to eq("Team Küche")
    end
  end

  describe Fin::MossDepartmentsController, type: :controller do
    before { sign_in(accountant) }

    it "counts the current teams and their current users" do
      archived = MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Alt", status: "ARCHIVED",
        moss_department_uuid: department.moss_department_uuid)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "ACTIVE", moss_team_uuid: archived.moss_team_uuid)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "DEACTIVATED", moss_team_uuid: team.moss_team_uuid)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: "ACTIVE", moss_team_uuid: team.moss_team_uuid,
        moss_removed_at: Time.current)
      get :index

      row = doc.css("tr.exp-row").find { |tr| tr.text.include?("Abteilung Logistik") }
      counts = row.css("td").map { |td| td.text.squish }.last(3).first(2)
      # Team Küche only, with Erika only.
      expect(counts).to eq(%w[1 1])
    end

    it "shows the department's teams and their users as tables, deactivated users left out" do
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Dora", last_name: "Alt",
        email: "dora.alt@example.com", status: "DEACTIVATED", moss_team_uuid: team.moss_team_uuid)
      get :show, params: {id: department.id}

      expect(doc.at_css("a[href='#{moss_team_path(team)}']").text).to eq("Team Küche")
      user_rows = doc.css("tr.exp-row[data-bs-target^='#mdu_']").map { |tr| tr.text.squish }
      expect(user_rows).to contain_exactly(include("Erika Beispiel"))

      get :show, params: {id: department.id, uu: "status.active+invited+deactivated"}
      user_rows = doc.css("tr.exp-row[data-bs-target^='#mdu_']").map { |tr| tr.text.squish }
      expect(user_rows).to contain_exactly(include("Erika Beispiel"), include("Dora Alt"))
    end

    it "lists only users of teams in Moss and not archived, like the count" do
      archived = MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Alt", status: "ARCHIVED",
        moss_department_uuid: department.moss_department_uuid)
      MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Otto", last_name: "Alt", status: "ACTIVE",
        moss_team_uuid: archived.moss_team_uuid)
      get :show, params: {id: department.id}

      user_rows = doc.css("tr.exp-row[data-bs-target^='#mdu_']").map { |tr| tr.text.squish }
      expect(user_rows).to contain_exactly(include("Erika Beispiel"))
    end

    it "hands the posted team filter on to the department's page (PRG)" do
      post :apply_teams, params: {id: department.id, filter_json: [[["status", "in", "ACTIVE"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(response.location).to start_with(moss_department_url(department))
      expect(response.location).to include("tf=")
    end

    it "saves the comment only" do
      patch :update, params: {id: department.id, moss_department: {comment: "Notiz", name: "Anders"}}

      expect(department.reload.comment).to eq("Notiz")
      expect(department.name).to eq("Abteilung Logistik")
    end
  end
end
