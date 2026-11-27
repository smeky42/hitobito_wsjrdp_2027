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
  before_all(setup_fixtures: true) {}

  let_it_be(:accountant, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:auditor, refind: true) do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person
  end
  let_it_be(:reader, refind: true) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  let_it_be(:department, refind: true) do
    MossDepartment.create!(moss_department_uuid: SecureRandom.uuid, name: "Abteilung Logistik")
  end
  let_it_be(:team, refind: true) do
    MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Küche", status: "ACTIVE",
      moss_department_uuid: department.moss_department_uuid)
  end
  let_it_be(:empty_team) { MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Leer", status: "ARCHIVED") }
  let_it_be(:user, refind: true) do
    MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Erika", last_name: "Beispiel",
      email: "erika.beispiel@example.com", status: "ACTIVE", roles: %w[USER TEAMLEAD],
      moss_team_uuid: team.moss_team_uuid, person: people(:yp_a_1))
  end
  let_it_be(:invited) do
    MossUser.create!(moss_user_uuid: SecureRandom.uuid, first_name: "Max", last_name: "Muster",
      email: "max.muster@example.com", status: "INVITED", roles: %w[USER], manager_uuid: user.moss_user_uuid,
      moss_team_uuid: SecureRandom.uuid)
  end

  before_all { team.update!(team_lead_uuid: user.moss_user_uuid) }

  def create_user(status, team_uuid = team.moss_team_uuid, **attrs)
    MossUser.create!(moss_user_uuid: SecureRandom.uuid, status: status, moss_team_uuid: team_uuid, **attrs)
  end

  def archived_team
    MossTeam.create!(moss_team_uuid: SecureRandom.uuid, name: "Team Alt", status: "ARCHIVED",
      moss_department_uuid: department.moss_department_uuid)
  end

  def listed = controller.rows.page.to_a

  describe Fin::MossUsersController, type: :controller do
    describe "GET index" do
      before { sign_in(accountant) }

      it "filters by status" do
        get :index, params: {f: "!(!(!(st,in,INVITED)))"}
        expect(listed).to eq([invited])
      end

      it "filters by role, any of the chosen" do
        get :index, params: {f: "!(!(!(rl,in,TEAMLEAD)))"}
        expect(listed).to eq([user])
      end

      it "filters by a missing person link" do
        get :index, params: {f: "!(!(!(pl,in,nein)))"}
        expect(listed).to eq([invited])
      end

      it "filters by team" do
        get :index, params: {f: "!(!(!(tm,in,'#{team.moss_team_uuid}')))"}
        expect(listed).to eq([user])
      end

      it "filters by name" do
        get :index, params: {f: "!(!(!(q,ct,'erika beis')))"}
        expect(listed).to eq([user])
      end

      it "shows users of other or no status by default, as the counts do, but no deactivated ones" do
        hidden = create_user("HIDDEN")
        without = create_user(nil)
        create_user("DEACTIVATED")
        get :index

        expect(listed).to contain_exactly(user, invited, hidden, without)
      end

      it "hides users of other or no status on request" do
        create_user("HIDDEN")
        create_user(nil)
        get :index, params: {u: "status.active+invited"}

        expect(listed).to contain_exactly(user, invited)
      end

      it "drops a team condition whose value is no uuid instead of failing" do
        get :index, params: {f: "!(!(!(tm,in,'x')))"}

        expect(response).to be_successful
        expect(listed).to include(user)
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

      def turbo_update(frame)
        request.headers["Turbo-Frame"] = frame
        request.accept = "text/vnd.turbo-stream.html, text/html"
        patch :update, params: {id: user.id, moss_user: {comment: "Neu"}}
        Nokogiri::HTML(response.body).at_css("turbo-stream[action='redirect_top']")["url"]
      end

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

      it "unlinks the person when the field is cleared" do
        patch :update, params: {id: user.id, moss_user: {person_id: ""}}

        expect(user.reload.person).to be_nil
      end

      it "answers a save from a row of a table on another page with the detail in that row" do
        request.headers["Turbo-Frame"] = "bkframe-mtu_#{team.id}-#{user.id}"
        patch :update, params: {id: user.id, moss_user: {comment: "Neu"}}

        expect(response).to redirect_to(moss_user_path(user))
      end

      it "answers a save from a row by reloading the list with the row open" do
        expect(turbo_update("bkframe-mu-#{user.id}"))
          .to eq(moss_users_path(Fin::MossUsersController::POLICY.param_name(:open) => user.id))
      end

      it "answers a save from the page's frame by reloading the page" do
        expect(turbo_update("bkframe-mupage-#{user.id}")).to eq(moss_user_path(user))
      end

      it "takes no return_url with another scheme" do
        get :edit, params: {id: user.id, return_url: "javascript:alert(1)"}
        expect(controller.send(:cancel_url)).to eq(moss_user_path(user))
      end

      it "takes no return_url to another host" do
        get :edit, params: {id: user.id, return_url: "//evil.example"}
        expect(controller.send(:cancel_url)).to eq(moss_user_path(user))
      end

      it "takes a return_url that is a path on this site" do
        get :edit, params: {id: user.id, return_url: "/fin/moss/teams"}
        expect(controller.send(:cancel_url)).to eq("/fin/moss/teams")
      end
    end

    describe "the audit tier" do
      before { sign_in(auditor) }

      it "reads the list" do
        get :index
        expect(response).to be_successful
      end

      it "reads the page" do
        get :show, params: {id: user.id}
        expect(response).to be_successful
      end

      it "may not open the edit page" do
        expect { get :edit, params: {id: user.id} }.to raise_error(CanCan::AccessDenied)
      end

      it "may not save" do
        expect { patch :update, params: {id: user.id, moss_user: {comment: "x"}} }
          .to raise_error(CanCan::AccessDenied)
        expect(user.reload.comment).to eq("")
      end
    end

    describe "the read tier" do
      before { sign_in(reader) }

      it "may not read the list" do
        expect { get :index }.to raise_error(CanCan::AccessDenied)
      end

      it "may not read the page" do
        expect { get :show, params: {id: user.id} }.to raise_error(CanCan::AccessDenied)
      end
    end

    it "is closed to a person without finance rights" do
      sign_in(people(:yp_a_1))
      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe Fin::MossTeamsController, type: :controller do
    before { sign_in(accountant) }

    it "counts as Benutzer the users in Moss that are not deactivated, linked to a person or not" do
      create_user("DEACTIVATED")
      create_user("ACTIVE", moss_removed_at: Time.current)
      create_user("INVITED")
      get :index

      # Erika (with a person) and the invited user (without one).
      expect(listed.find { |row| row.id == team.id }.user_count).to eq(2)
    end

    it "sorts by the user count" do
      2.times { create_user("ACTIVE", empty_team.moss_team_uuid) }
      get :index, params: {u: "status.active+archived", s: "uc~"}
      expect(listed).to eq([empty_team, team])
    end

    it "filters on the user count" do
      get :index, params: {u: "status.active+archived", f: "!(!(!(uc,nz)))"}
      expect(listed).to eq([team])
    end

    it "shows the active teams by default" do
      get :index
      expect(listed).to eq([team])
    end

    it "shows the archived teams once chosen" do
      get :index, params: {u: "status.archived"}
      expect(listed).to eq([empty_team])
    end

    it "filters by status" do
      get :index, params: {u: "status.active+archived+others", f: "!(!(!(st,in,ARCHIVED)))"}
      expect(listed).to eq([empty_team])
    end

    it "filters by department" do
      get :index, params: {f: "!(!(!(dp,in,'#{department.moss_department_uuid}')))"}
      expect(listed).to eq([team])
    end

    describe "the team's users" do
      let!(:deactivated) { create_user("DEACTIVATED", first_name: "Dora", last_name: "Alt") }

      def team_users = controller.team_users.page.to_a

      it "leaves deactivated users out by default" do
        get :show, params: {id: team.id}
        expect(team_users).to eq([user])
      end

      it "shows them once the quick filter is off" do
        get :show, params: {id: team.id, uu: "status.active+invited+deactivated"}
        expect(team_users).to contain_exactly(user, deactivated)
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

    def department_users = controller.department_users.page.to_a

    it "counts the current teams and their current users" do
      create_user("ACTIVE", archived_team.moss_team_uuid)
      create_user("DEACTIVATED")
      create_user("ACTIVE", moss_removed_at: Time.current)
      get :index

      # Team Küche only, with Erika only.
      row = listed.find { |r| r.id == department.id }
      expect([row.team_count, row.user_count]).to eq([1, 1])
    end

    it "lists the department's teams" do
      get :show, params: {id: department.id}
      expect(controller.department_teams.page.to_a).to eq([team])
    end

    it "leaves deactivated users of the department out by default" do
      create_user("DEACTIVATED")
      get :show, params: {id: department.id}
      expect(department_users).to eq([user])
    end

    it "shows deactivated users once the quick filter is off" do
      dora = create_user("DEACTIVATED")
      get :show, params: {id: department.id, uu: "status.active+invited+deactivated"}
      expect(department_users).to contain_exactly(user, dora)
    end

    it "lists only users of teams in Moss and not archived, like the count" do
      create_user("ACTIVE", archived_team.moss_team_uuid)
      get :show, params: {id: department.id}
      expect(department_users).to eq([user])
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
