defmodule Braintrust.SpanTest do
  use ExUnit.Case, async: true

  alias Braintrust.Span

  describe "struct" do
    test "creates span with all fields" do
      span = %Span{
        id: "span_123",
        span_id: "s_123",
        root_span_id: "r_123",
        span_parents: ["p_123"],
        input: %{messages: [%{role: "user", content: "Hello"}]},
        output: "Hi there!",
        expected: "A greeting",
        scores: %{quality: 0.9},
        metadata: %{model: "gpt-4"},
        metrics: %{latency_ms: 250},
        tags: ["production"],
        created_at: ~U[2024-01-15 14:15:22Z],
        error: nil
      }

      assert span.id == "span_123"
      assert span.input == %{messages: [%{role: "user", content: "Hello"}]}
      assert span.scores == %{quality: 0.9}
    end

    test "creates span with minimal fields" do
      span = %Span{
        input: %{query: "test"},
        output: "result"
      }

      assert span.input == %{query: "test"}
      assert span.output == "result"
      assert span.scores == nil
    end
  end

  describe "to_map/1" do
    test "converts span to map removing nil values" do
      span = %Span{
        input: %{query: "test"},
        output: "result",
        scores: %{quality: 0.9}
      }

      map = Span.to_map(span)

      assert map[:input] == %{query: "test"}
      assert map[:output] == "result"
      assert map[:scores] == %{quality: 0.9}
      refute Map.has_key?(map, :id)
      refute Map.has_key?(map, :metadata)
      refute Map.has_key?(map, :error)
    end

    test "preserves all non-nil values" do
      span = %Span{
        id: "span_123",
        input: %{messages: []},
        output: "response",
        expected: "expected",
        scores: %{accuracy: 1.0},
        metadata: %{env: "test"},
        metrics: %{latency_ms: 100},
        tags: ["test"],
        error: "Something went wrong"
      }

      map = Span.to_map(span)

      assert map[:id] == "span_123"
      assert map[:input] == %{messages: []}
      assert map[:output] == "response"
      assert map[:expected] == "expected"
      assert map[:scores] == %{accuracy: 1.0}
      assert map[:metadata] == %{env: "test"}
      assert map[:metrics] == %{latency_ms: 100}
      assert map[:tags] == ["test"]
      assert map[:error] == "Something went wrong"
    end

    test "handles span_parents list" do
      span = %Span{
        input: %{},
        span_parents: ["parent_1", "parent_2"]
      }

      map = Span.to_map(span)

      assert map[:span_parents] == ["parent_1", "parent_2"]
    end
  end
end
