defmodule Braintrust.FunctionTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Function}

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
    test "returns list of function structs" do
      response = %{
        "objects" => [
          %{
            "id" => "func_1",
            "name" => "scorer-1",
            "project_id" => "proj_1",
            "function_type" => "scorer"
          },
          %{
            "id" => "func_2",
            "name" => "tool-1",
            "project_id" => "proj_1",
            "function_type" => "tool"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, functions} = Function.list()
      assert length(functions) == 2
      assert [%Function{id: "func_1"}, %Function{id: "func_2"}] = functions

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:function_type] == "scorer"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Function.list(project_id: "proj_123", function_type: "scorer")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Function.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of function structs" do
      response = %{
        "objects" => [
          %{"id" => "func_1", "name" => "f1", "project_id" => "proj_1", "function_type" => "tool"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      functions = Function.stream() |> Enum.to_list()
      assert [%Function{id: "func_1"}] = functions

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns function struct on success" do
      response = %{
        "id" => "func_123",
        "name" => "my-scorer",
        "project_id" => "proj_1",
        "slug" => "my-scorer-v1",
        "function_type" => "scorer",
        "function_data" => %{
          "type" => "code",
          "data" => %{"runtime" => "node", "code" => "..."}
        },
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/function/func_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_123")
      assert %Function{id: "func_123", name: "my-scorer"} = func
      assert func.function_type == "scorer"
      assert func.function_data["type"] == "code"
      assert %DateTime{} = func.created_at
    end

    test "supports version parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:version] == "v2"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "func_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _func} = Function.get("func_123", version: "v2")
    end

    test "supports xact_id parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:xact_id] == "xact_abc123"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "func_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _func} = Function.get("func_123", xact_id: "xact_abc123")
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Function not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Function.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns function struct" do
      response = %{
        "id" => "func_new",
        "project_id" => "proj_123",
        "name" => "new-scorer",
        "slug" => "new-scorer-v1",
        "function_type" => "scorer"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json][:name] == "new-scorer"
        assert opts[:json][:project_id] == "proj_123"
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "new-scorer",
                 slug: "new-scorer-v1",
                 function_type: "scorer"
               })

      assert %Function{id: "func_new", name: "new-scorer"} = func
    end

    test "creates function with function_data" do
      function_data = %{
        type: "code",
        data: %{runtime: "node", code: "export default async function() { return 1.0; }"}
      }

      response = %{
        "id" => "func_new",
        "project_id" => "proj_123",
        "name" => "code-scorer",
        "function_type" => "scorer",
        "function_data" => %{
          "type" => "code",
          "data" => %{
            "runtime" => "node",
            "code" => "export default async function() { return 1.0; }"
          }
        }
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:json][:function_data] == function_data
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "code-scorer",
                 function_type: "scorer",
                 function_data: function_data
               })

      assert func.function_data["type"] == "code"
    end

    test "returns existing function if name exists (idempotent)" do
      response = %{
        "id" => "func_existing",
        "project_id" => "proj_123",
        "name" => "existing-func"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "existing-func"
               })

      assert func.id == "func_existing"
    end

    test "returns error on validation failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 400,
           body: %{"error" => %{"message" => "project_id is required"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :bad_request, message: "project_id is required"}} =
               Function.create(%{name: "test"})
    end
  end

  describe "update/3" do
    test "updates and returns function struct" do
      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "scorer",
        "description" => "Updated description"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.update("func_123", %{description: "Updated description"})
      assert func.description == "Updated description"
    end

    test "updates function_data" do
      new_function_data = %{
        type: "llm",
        data: %{model: "gpt-4", messages: [%{role: "system", content: "Rate quality..."}]}
      }

      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "scorer",
        "function_data" => %{
          "type" => "llm",
          "data" => %{
            "model" => "gpt-4",
            "messages" => [%{"role" => "system", "content" => "Rate quality..."}]
          }
        }
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json][:function_data] == new_function_data
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.update("func_123", %{function_data: new_function_data})
      assert func.function_data["type"] == "llm"
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Function not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Function.update("invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns function with deleted_at set" do
      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "deleted-func",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.delete("func_123")
      assert %DateTime{} = func.deleted_at
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

      assert {:error, %Error{type: :permission_denied}} = Function.delete("func_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "func_1",
        "org_id" => "org_1",
        "project_id" => "proj_1",
        "name" => "test-function",
        "slug" => "test-function-v1",
        "description" => "Test description",
        "function_type" => "scorer",
        "function_data" => %{"type" => "code", "data" => %{}},
        "origin" => %{"type" => "api"},
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.id == "func_1"
      assert func.org_id == "org_1"
      assert func.project_id == "proj_1"
      assert func.name == "test-function"
      assert func.slug == "test-function-v1"
      assert func.description == "Test description"
      assert func.function_type == "scorer"
      assert func.function_data == %{"type" => "code", "data" => %{}}
      assert func.origin == %{"type" => "api"}
      assert func.user_id == "user_1"
      assert func.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = func.created_at
      assert func.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "func_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.project_id == nil
      assert func.slug == nil
      assert func.function_type == nil
      assert func.function_data == nil
      assert func.origin == nil
      assert func.created_at == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "func_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.created_at == nil
    end

    test "maps 'created' API field to 'created_at' struct field" do
      response = %{
        "id" => "func_1",
        "name" => "test",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      # Verify that the 'created' field from API is mapped to created_at in struct
      assert %DateTime{} = func.created_at
      assert func.created_at.year == 2024
    end
  end
end
