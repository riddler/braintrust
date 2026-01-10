defmodule Braintrust.ExperimentTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Experiment}

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
    test "returns list of experiment structs" do
      response = %{
        "objects" => [
          %{
            "id" => "exp_1",
            "project_id" => "proj_1",
            "name" => "experiment-1",
            "public" => false
          },
          %{
            "id" => "exp_2",
            "project_id" => "proj_1",
            "name" => "experiment-2",
            "public" => true
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, experiments} = Experiment.list()
      assert length(experiments) == 2
      assert [%Experiment{id: "exp_1"}, %Experiment{id: "exp_2"}] = experiments

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:experiment_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Experiment.list(project_id: "proj_123", experiment_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Experiment.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of experiment structs" do
      response = %{
        "objects" => [
          %{"id" => "exp_1", "project_id" => "proj_1", "name" => "e1", "public" => false}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      experiments = Experiment.stream() |> Enum.to_list()
      assert [%Experiment{id: "exp_1"}] = experiments

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns experiment struct on success" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "my-experiment",
        "description" => "Test experiment",
        "public" => false,
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/experiment/exp_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_123")
      assert %Experiment{id: "exp_123", name: "my-experiment"} = experiment
      assert %DateTime{} = experiment.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Experiment not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Experiment.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns experiment struct" do
      response = %{
        "id" => "exp_new",
        "project_id" => "proj_123",
        "name" => "new-experiment",
        "public" => false
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{project_id: "proj_123", name: "new-experiment"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.create(%{project_id: "proj_123", name: "new-experiment"})

      assert %Experiment{id: "exp_new", name: "new-experiment"} = experiment
    end

    test "returns existing experiment if name exists (idempotent)" do
      response = %{
        "id" => "exp_existing",
        "project_id" => "proj_123",
        "name" => "existing-experiment",
        "public" => false
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.create(%{project_id: "proj_123", name: "existing-experiment"})

      assert experiment.id == "exp_existing"
    end
  end

  describe "update/3" do
    test "updates and returns experiment struct" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "experiment",
        "description" => "Updated description",
        "public" => false
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.update("exp_123", %{description: "Updated description"})

      assert experiment.description == "Updated description"
    end
  end

  describe "delete/2" do
    test "deletes and returns experiment with deleted_at set" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "deleted-experiment",
        "public" => false,
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.delete("exp_123")
      assert %DateTime{} = experiment.deleted_at
    end
  end

  describe "insert/3" do
    test "inserts events and returns result" do
      events = [
        %{
          input: %{messages: [%{role: "user", content: "Hello"}]},
          output: "Hi there!",
          scores: %{quality: 0.9}
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/insert"
        assert opts[:json] == %{events: events}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Experiment.insert("exp_123", events)
      assert result["row_ids"] == ["row_1"]
    end
  end

  describe "fetch/3" do
    test "fetches events with pagination" do
      response = %{
        "events" => [
          %{"id" => "evt_1", "input" => %{}, "output" => "response"}
        ],
        "cursor" => "next_cursor"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/fetch"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, result} = Experiment.fetch("exp_123", limit: 50)
      assert length(result["events"]) == 1
      assert result["cursor"] == "next_cursor"
    end
  end

  describe "fetch_stream/3" do
    test "streams through events across pages" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "events" => [%{"id" => "evt_1"}, %{"id" => "evt_2"}],
                 "cursor" => "cursor_1"
               },
               headers: []
             }}

          1 ->
            assert opts[:json][:cursor] == "cursor_1"

            {:ok,
             %Req.Response{
               status: 200,
               body: %{"events" => [%{"id" => "evt_3"}]},
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      events = Experiment.fetch_stream("exp_123") |> Enum.to_list()
      assert length(events) == 3
      assert [%{"id" => "evt_1"}, %{"id" => "evt_2"}, %{"id" => "evt_3"}] = events

      Agent.stop(agent)
    end
  end

  describe "feedback/3" do
    test "submits feedback for events" do
      feedback = [
        %{
          id: "evt_123",
          scores: %{human_rating: 0.8},
          comment: "Good response"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/feedback"
        assert opts[:json] == %{feedback: feedback}
        {:ok, %Req.Response{status: 200, body: %{}, headers: []}}
      end)

      assert {:ok, _result} = Experiment.feedback("exp_123", feedback)
    end
  end

  describe "summarize/2" do
    test "returns experiment summary" do
      response = %{
        "project_name" => "my-project",
        "experiment_name" => "my-experiment",
        "scores" => [
          %{"name" => "accuracy", "score" => 0.85}
        ],
        "metrics" => [
          %{"name" => "latency", "metric" => 250, "unit" => "ms"}
        ]
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/experiment/exp_123/summarize"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, summary} = Experiment.summarize("exp_123")
      assert summary["experiment_name"] == "my-experiment"
      assert length(summary["scores"]) == 1
    end

    test "supports comparison experiment" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:comparison_experiment_id] == "exp_baseline"
        {:ok, %Req.Response{status: 200, body: %{"scores" => []}, headers: []}}
      end)

      assert {:ok, _summary} =
               Experiment.summarize("exp_123", comparison_experiment_id: "exp_baseline")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "exp_1",
        "project_id" => "proj_1",
        "name" => "test",
        "description" => "Test description",
        "repo_info" => %{"branch" => "main", "commit" => "abc123"},
        "base_exp_id" => "exp_base",
        "dataset_id" => "ds_1",
        "dataset_version" => "v1",
        "public" => true,
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_1")
      assert experiment.id == "exp_1"
      assert experiment.project_id == "proj_1"
      assert experiment.description == "Test description"
      assert experiment.repo_info == %{"branch" => "main", "commit" => "abc123"}
      assert experiment.base_exp_id == "exp_base"
      assert experiment.dataset_id == "ds_1"
      assert experiment.dataset_version == "v1"
      assert experiment.public == true
      assert experiment.user_id == "user_1"
      assert experiment.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = experiment.created_at
      assert experiment.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "exp_1",
        "project_id" => "proj_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_1")
      assert experiment.description == nil
      assert experiment.repo_info == nil
      assert experiment.public == false
      assert experiment.metadata == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "exp_1",
        "project_id" => "proj_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_1")
      assert experiment.created_at == nil
    end
  end

  describe "fetch_stream/3 edge cases" do
    test "handles empty events list" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      events = Experiment.fetch_stream("exp_123") |> Enum.to_list()
      assert events == []

      Agent.stop(agent)
    end

    test "handles response without cursor" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{status: 200, body: %{"events" => [%{"id" => "evt_1"}]}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      events = Experiment.fetch_stream("exp_123") |> Enum.to_list()
      assert [%{"id" => "evt_1"}] = events

      Agent.stop(agent)
    end

    test "handles response without events key" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 200, body: %{}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      events = Experiment.fetch_stream("exp_123") |> Enum.to_list()
      assert events == []

      Agent.stop(agent)
    end

    test "propagates fetch errors via throw" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      # The fetch_events_page function throws {:fetch_error, error} when Client.post returns {:error, _}
      assert catch_throw(Experiment.fetch_stream("exp_123") |> Enum.to_list()) ==
               {:fetch_error,
                %Braintrust.Error{
                  type: :server_error,
                  message: "Server error",
                  code: nil,
                  status: 500,
                  retry_after: nil
                }}

      Agent.stop(agent)
    end
  end

  describe "create/2 with options" do
    test "creates experiment with metadata" do
      response = %{
        "id" => "exp_new",
        "project_id" => "proj_123",
        "name" => "new-experiment",
        "metadata" => %{"model" => "gpt-4"},
        "public" => false
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json][:metadata] == %{model: "gpt-4"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.create(%{
                 project_id: "proj_123",
                 name: "new-experiment",
                 metadata: %{model: "gpt-4"}
               })

      assert experiment.metadata == %{"model" => "gpt-4"}
    end
  end

  describe "update/3 error handling" do
    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Experiment not found"}},
           headers: []
         }}
      end)

      assert {:error, %Braintrust.Error{type: :not_found}} =
               Experiment.update("exp_invalid", %{name: "new-name"})
    end
  end

  describe "insert/3 validation" do
    test "requires events to be a list" do
      assert_raise FunctionClauseError, fn ->
        Experiment.insert("exp_123", %{invalid: "not a list"})
      end
    end
  end

  describe "feedback/3 validation" do
    test "requires feedback to be a list" do
      assert_raise FunctionClauseError, fn ->
        Experiment.feedback("exp_123", %{invalid: "not a list"})
      end
    end
  end

  describe "summarize/2 with options" do
    test "supports summarize_scores option" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:summarize_scores] == true
        {:ok, %Req.Response{status: 200, body: %{"scores" => []}, headers: []}}
      end)

      assert {:ok, _summary} = Experiment.summarize("exp_123", summarize_scores: true)
    end
  end
end
