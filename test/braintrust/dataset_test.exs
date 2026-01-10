defmodule Braintrust.DatasetTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Dataset, Error}

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
    test "returns list of dataset structs" do
      response = %{
        "objects" => [
          %{
            "id" => "ds_1",
            "project_id" => "proj_1",
            "name" => "dataset-1"
          },
          %{
            "id" => "ds_2",
            "project_id" => "proj_1",
            "name" => "dataset-2"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, datasets} = Dataset.list()
      assert length(datasets) == 2
      assert [%Dataset{id: "ds_1"}, %Dataset{id: "ds_2"}] = datasets

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:dataset_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Dataset.list(project_id: "proj_123", dataset_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Dataset.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of dataset structs" do
      response = %{
        "objects" => [
          %{"id" => "ds_1", "project_id" => "proj_1", "name" => "d1"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      datasets = Dataset.stream() |> Enum.to_list()
      assert [%Dataset{id: "ds_1"}] = datasets

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns dataset struct on success" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "my-dataset",
        "description" => "Test dataset",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/dataset/ds_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_123")
      assert %Dataset{id: "ds_123", name: "my-dataset"} = dataset
      assert %DateTime{} = dataset.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Dataset not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Dataset.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns dataset struct" do
      response = %{
        "id" => "ds_new",
        "project_id" => "proj_123",
        "name" => "new-dataset"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{project_id: "proj_123", name: "new-dataset"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.create(%{project_id: "proj_123", name: "new-dataset"})
      assert %Dataset{id: "ds_new", name: "new-dataset"} = dataset
    end

    test "returns existing dataset if name exists (idempotent)" do
      response = %{
        "id" => "ds_existing",
        "project_id" => "proj_123",
        "name" => "existing-dataset"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.create(%{project_id: "proj_123", name: "existing-dataset"})
      assert dataset.id == "ds_existing"
    end
  end

  describe "update/3" do
    test "updates and returns dataset struct" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "dataset",
        "description" => "Updated description"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.update("ds_123", %{description: "Updated description"})
      assert dataset.description == "Updated description"
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Dataset not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} =
               Dataset.update("ds_invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns dataset with deleted_at set" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "deleted-dataset",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.delete("ds_123")
      assert %DateTime{} = dataset.deleted_at
    end
  end

  describe "insert/3" do
    test "inserts records and returns result" do
      records = [
        %{
          input: %{question: "What is 2+2?"},
          expected: "4"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/insert"
        assert opts[:json] == %{events: records}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Dataset.insert("ds_123", records)
      assert result["row_ids"] == ["row_1"]
    end

    test "inserts records with Span structs" do
      spans = [
        %Braintrust.Span{
          input: %{question: "What is 2+2?"},
          expected: "4"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/insert"

        # Span should be converted to map with nil values removed
        [record] = opts[:json][:events]
        assert record[:input] == %{question: "What is 2+2?"}
        assert record[:expected] == "4"
        refute Map.has_key?(record, :id)

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Dataset.insert("ds_123", spans)
      assert result["row_ids"] == ["row_1"]
    end

    test "inserts mixed records (maps and Span structs)" do
      records = [
        %{input: %{q: "map"}, expected: "map answer"},
        %Braintrust.Span{input: %{q: "span"}, expected: "span answer"}
      ]

      expect(Req, :request, fn _client, opts ->
        [record1, record2] = opts[:json][:events]

        # Map record unchanged
        assert record1 == %{input: %{q: "map"}, expected: "map answer"}

        # Span converted to map
        assert record2[:input] == %{q: "span"}
        assert record2[:expected] == "span answer"

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1", "row_2"]}, headers: []}}
      end)

      assert {:ok, result} = Dataset.insert("ds_123", records)
      assert length(result["row_ids"]) == 2
    end

    test "requires records to be a list" do
      assert_raise FunctionClauseError, fn ->
        Dataset.insert("ds_123", %{invalid: "not a list"})
      end
    end
  end

  describe "fetch/3" do
    test "fetches records with pagination" do
      response = %{
        "events" => [
          %{"id" => "rec_1", "input" => %{question: "test"}, "expected" => "answer"}
        ],
        "cursor" => "next_cursor"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/fetch"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, result} = Dataset.fetch("ds_123", limit: 50)
      assert length(result["events"]) == 1
      assert result["cursor"] == "next_cursor"
    end
  end

  describe "fetch_stream/3" do
    test "streams through records across pages" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "events" => [%{"id" => "rec_1"}, %{"id" => "rec_2"}],
                 "cursor" => "cursor_1"
               },
               headers: []
             }}

          1 ->
            assert opts[:json][:cursor] == "cursor_1"

            {:ok,
             %Req.Response{
               status: 200,
               body: %{"events" => [%{"id" => "rec_3"}]},
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      records = Dataset.fetch_stream("ds_123") |> Enum.to_list()
      assert length(records) == 3
      assert [%{"id" => "rec_1"}, %{"id" => "rec_2"}, %{"id" => "rec_3"}] = records

      Agent.stop(agent)
    end

    test "handles empty records list" do
      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, empty_events_stub(agent))

      records = Dataset.fetch_stream("ds_123") |> Enum.to_list()
      assert records == []

      Agent.stop(agent)
    end

    test "propagates fetch errors via throw" do
      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, error_on_first_page_stub(agent))

      assert catch_throw(Dataset.fetch_stream("ds_123") |> Enum.to_list()) ==
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

  describe "feedback/3" do
    test "submits feedback for records" do
      feedback = [
        %{
          id: "rec_123",
          scores: %{quality: 0.9},
          comment: "Good test case"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/feedback"
        assert opts[:json] == %{feedback: feedback}
        {:ok, %Req.Response{status: 200, body: %{}, headers: []}}
      end)

      assert {:ok, _result} = Dataset.feedback("ds_123", feedback)
    end

    test "requires feedback to be a list" do
      assert_raise FunctionClauseError, fn ->
        Dataset.feedback("ds_123", %{invalid: "not a list"})
      end
    end
  end

  describe "summarize/2" do
    test "returns dataset summary" do
      response = %{
        "project_name" => "my-project",
        "dataset_name" => "my-dataset",
        "data_summary" => %{
          "total_records" => 100
        }
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/dataset/ds_123/summarize"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, summary} = Dataset.summarize("ds_123")
      assert summary["dataset_name"] == "my-dataset"
    end

    test "supports summarize_data option" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:summarize_data] == true
        {:ok, %Req.Response{status: 200, body: %{"data_summary" => %{}}, headers: []}}
      end)

      assert {:ok, _summary} = Dataset.summarize("ds_123", summarize_data: true)
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test",
        "description" => "Test description",
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.id == "ds_1"
      assert dataset.project_id == "proj_1"
      assert dataset.description == "Test description"
      assert dataset.user_id == "user_1"
      assert dataset.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = dataset.created_at
      assert dataset.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.description == nil
      assert dataset.metadata == nil
      assert dataset.user_id == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.created_at == nil
    end
  end
end
