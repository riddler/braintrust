defmodule Braintrust.ProjectTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Config, Error, Project}

  setup do
    original_api_key = System.get_env("BRAINTRUST_API_KEY")
    System.delete_env("BRAINTRUST_API_KEY")
    Config.clear()
    Config.configure(api_key: "sk-test")

    on_exit(fn ->
      if original_api_key do
        System.put_env("BRAINTRUST_API_KEY", original_api_key)
      end
    end)

    :ok
  end

  describe "list/1" do
    test "returns list of project structs" do
      response = %{
        "objects" => [
          %{"id" => "proj_1", "name" => "project-1", "org_id" => "org_1"},
          %{"id" => "proj_2", "name" => "project-2", "org_id" => "org_1"}
        ]
      }

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 200, body: response, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, projects} = Project.list()
      assert length(projects) == 2
      assert [%Project{id: "proj_1"}, %Project{id: "proj_2"}] = projects

      Agent.stop(agent)
    end

    test "passes query parameters" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            # Verify parameters on first call
            assert opts[:params][:limit] == 10
            assert opts[:params][:project_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Project.list(limit: 10, project_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Project.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of project structs" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"objects" => [%{"id" => "proj_1", "name" => "p1", "org_id" => "org"}]},
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      projects = Project.stream() |> Enum.to_list()
      assert [%Project{id: "proj_1"}] = projects

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns project struct on success" do
      response = %{
        "id" => "proj_123",
        "name" => "my-project",
        "org_id" => "org_1",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/project/proj_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_123")
      assert %Project{id: "proj_123", name: "my-project"} = project
      assert %DateTime{} = project.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Project not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Project.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns project struct" do
      response = %{
        "id" => "proj_new",
        "name" => "new-project",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{name: "new-project"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.create(%{name: "new-project"})
      assert %Project{id: "proj_new", name: "new-project"} = project
    end

    test "returns existing project if name exists (idempotent)" do
      response = %{
        "id" => "proj_existing",
        "name" => "existing-project",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.create(%{name: "existing-project"})
      assert project.id == "proj_existing"
    end

    test "returns error on validation failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 400,
           body: %{"error" => %{"message" => "Name is required"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :bad_request, message: "Name is required"}} =
               Project.create(%{})
    end
  end

  describe "update/3" do
    test "updates and returns project struct" do
      response = %{
        "id" => "proj_123",
        "name" => "updated-name",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{name: "updated-name"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.update("proj_123", %{name: "updated-name"})
      assert project.name == "updated-name"
    end
  end

  describe "delete/2" do
    test "deletes and returns project with deleted_at set" do
      response = %{
        "id" => "proj_123",
        "name" => "deleted-project",
        "org_id" => "org_1",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.delete("proj_123")
      assert %DateTime{} = project.deleted_at
    end

    test "returns error on permission denied" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{"error" => %{"message" => "Permission denied"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :permission_denied}} = Project.delete("proj_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses datetime fields correctly" do
      response = %{
        "id" => "proj_1",
        "name" => "test",
        "org_id" => "org_1",
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_1")
      assert %DateTime{year: 2024, month: 1, day: 15} = project.created_at
      assert project.deleted_at == nil
    end

    test "maps 'created' API field to 'created_at' struct field" do
      response = %{
        "id" => "proj_1",
        "name" => "test",
        "org_id" => "org_1",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_1")
      # Verify that the 'created' field from API is mapped to created_at in struct
      assert %DateTime{} = project.created_at
      assert project.created_at.year == 2024
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "proj_1",
        "name" => "test",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_1")
      assert project.user_id == nil
      assert project.created_at == nil
      assert project.settings == nil
    end
  end
end
