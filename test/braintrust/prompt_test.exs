defmodule Braintrust.PromptTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Prompt}

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
    test "returns list of prompt structs" do
      response = %{
        "objects" => [
          %{
            "id" => "prompt_1",
            "name" => "prompt-1",
            "project_id" => "proj_1",
            "slug" => "prompt-1-v1"
          },
          %{
            "id" => "prompt_2",
            "name" => "prompt-2",
            "project_id" => "proj_1",
            "slug" => "prompt-2-v1"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, prompts} = Prompt.list()
      assert length(prompts) == 2
      assert [%Prompt{id: "prompt_1"}, %Prompt{id: "prompt_2"}] = prompts

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:prompt_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Prompt.list(project_id: "proj_123", prompt_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Prompt.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of prompt structs" do
      response = %{
        "objects" => [
          %{"id" => "prompt_1", "name" => "p1", "project_id" => "proj_1", "slug" => "p1-v1"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      prompts = Prompt.stream() |> Enum.to_list()
      assert [%Prompt{id: "prompt_1"}] = prompts

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns prompt struct on success" do
      response = %{
        "id" => "prompt_123",
        "name" => "my-prompt",
        "project_id" => "proj_1",
        "slug" => "my-prompt-v1",
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "{{query}}"}
        ],
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/prompt/prompt_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_123")
      assert %Prompt{id: "prompt_123", name: "my-prompt"} = prompt
      assert prompt.model == "gpt-4"
      assert length(prompt.messages) == 2
      assert %DateTime{} = prompt.created_at
    end

    test "supports version parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:version] == "v2"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "prompt_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _prompt} = Prompt.get("prompt_123", version: "v2")
    end

    test "supports xact_id parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:xact_id] == "xact_abc123"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "prompt_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _prompt} = Prompt.get("prompt_123", xact_id: "xact_abc123")
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Prompt not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Prompt.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns prompt struct" do
      response = %{
        "id" => "prompt_new",
        "project_id" => "proj_123",
        "name" => "new-prompt",
        "slug" => "new-prompt-v1",
        "model" => "gpt-4"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json][:name] == "new-prompt"
        assert opts[:json][:project_id] == "proj_123"
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, prompt} =
               Prompt.create(%{
                 project_id: "proj_123",
                 name: "new-prompt",
                 slug: "new-prompt-v1",
                 model: "gpt-4"
               })

      assert %Prompt{id: "prompt_new", name: "new-prompt"} = prompt
    end

    test "creates prompt with messages" do
      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "user", content: "{{input}}"}
      ]

      response = %{
        "id" => "prompt_new",
        "project_id" => "proj_123",
        "name" => "chat-prompt",
        "messages" => messages
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:json][:messages] == messages
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, prompt} =
               Prompt.create(%{
                 project_id: "proj_123",
                 name: "chat-prompt",
                 messages: messages
               })

      assert length(prompt.messages) == 2
    end

    test "returns existing prompt if name exists (idempotent)" do
      response = %{
        "id" => "prompt_existing",
        "project_id" => "proj_123",
        "name" => "existing-prompt"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} =
               Prompt.create(%{
                 project_id: "proj_123",
                 name: "existing-prompt"
               })

      assert prompt.id == "prompt_existing"
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
               Prompt.create(%{name: "test"})
    end
  end

  describe "update/3" do
    test "updates and returns prompt struct" do
      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "prompt",
        "model" => "gpt-4-turbo"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{model: "gpt-4-turbo"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.update("prompt_123", %{model: "gpt-4-turbo"})
      assert prompt.model == "gpt-4-turbo"
    end

    test "updates messages" do
      new_messages = [
        %{role: "system", content: "Updated system prompt."},
        %{role: "user", content: "{{query}}"}
      ]

      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "prompt",
        "messages" => new_messages
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json][:messages] == new_messages
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.update("prompt_123", %{messages: new_messages})
      assert length(prompt.messages) == 2
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Prompt not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Prompt.update("invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns prompt with deleted_at set" do
      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "deleted-prompt",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.delete("prompt_123")
      assert %DateTime{} = prompt.deleted_at
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

      assert {:error, %Error{type: :permission_denied}} = Prompt.delete("prompt_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "prompt_1",
        "org_id" => "org_1",
        "project_id" => "proj_1",
        "name" => "test-prompt",
        "slug" => "test-prompt-v1",
        "description" => "Test description",
        "model" => "gpt-4",
        "messages" => [%{"role" => "system", "content" => "Hello"}],
        "tools" => [%{"type" => "function", "function" => %{}}],
        "tool_choice" => "auto",
        "function_type" => "prompt",
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.id == "prompt_1"
      assert prompt.org_id == "org_1"
      assert prompt.project_id == "proj_1"
      assert prompt.name == "test-prompt"
      assert prompt.slug == "test-prompt-v1"
      assert prompt.description == "Test description"
      assert prompt.model == "gpt-4"
      assert length(prompt.messages) == 1
      assert length(prompt.tools) == 1
      assert prompt.tool_choice == "auto"
      assert prompt.function_type == "prompt"
      assert prompt.user_id == "user_1"
      assert prompt.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = prompt.created_at
      assert prompt.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "prompt_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.project_id == nil
      assert prompt.slug == nil
      assert prompt.model == nil
      assert prompt.messages == nil
      assert prompt.tools == nil
      assert prompt.created_at == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "prompt_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.created_at == nil
    end

    test "maps 'created' API field to 'created_at' struct field" do
      response = %{
        "id" => "prompt_1",
        "name" => "test",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      # Verify that the 'created' field from API is mapped to created_at in struct
      assert %DateTime{} = prompt.created_at
      assert prompt.created_at.year == 2024
    end
  end
end
