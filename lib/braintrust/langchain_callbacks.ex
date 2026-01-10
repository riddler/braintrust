defmodule Braintrust.LangChainCallbacks do
  @moduledoc """
  LangChain callback handler for Braintrust observability.

  Automatically logs LLM interactions to Braintrust when used with
  LangChain's LLMChain.

  ## Usage

      alias LangChain.Chains.LLMChain
      alias LangChain.ChatModels.ChatOpenAI
      alias LangChain.Message
      alias Braintrust.LangChainCallbacks

      {:ok, chain} =
        %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
        |> LLMChain.new!()
        |> LLMChain.add_callback(LangChainCallbacks.handler(
          project_id: "proj_xxx",
          metadata: %{"environment" => "production"},
          tags: ["chat"]
        ))
        |> LLMChain.add_message(Message.new_user!("Hello!"))
        |> LLMChain.run()

  ## Options

    * `:project_id` - Braintrust project ID (required)
    * `:metadata` - Additional metadata to attach to all spans (default: %{})
    * `:tags` - Tags to attach to spans (default: [])
    * `:api_key` - Override API key for logging requests
    * `:base_url` - Override base URL for logging requests

  ## What Gets Logged

  Each LLM interaction creates a log entry with:

    * `input` - Messages in OpenAI format (enables "Try prompt" button in UI)
    * `output` - Assistant response content
    * `metadata` - Model name, provider, status, plus custom metadata
    * `metrics` - Token usage (input_tokens, output_tokens, total_tokens)
    * `tags` - Custom tags
    * `error` - Error information if processing failed

  > #### Optional Dependency {: .info}
  >
  > This module requires the `langchain` package. Add it to your dependencies:
  >
  >     {:langchain, "~> 0.4"}
  >

  """

  alias Braintrust.Log

  # Process dictionary keys for cross-callback correlation
  @token_usage_key :braintrust_langchain_token_usage
  @first_token_time_key :braintrust_langchain_first_token_time
  @request_start_key :braintrust_langchain_request_start

  @type handler_opts :: [
          project_id: String.t(),
          metadata: map(),
          tags: [String.t()],
          api_key: String.t(),
          base_url: String.t()
        ]

  @doc """
  Creates a callback handler map for use with LLMChain.

  ## Examples

      handler = Braintrust.LangChainCallbacks.handler(project_id: "proj_xxx")

      chain
      |> LLMChain.add_callback(handler)
      |> LLMChain.run()

  """
  @spec handler(handler_opts()) :: map()
  def handler(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    base_metadata = Keyword.get(opts, :metadata, %{})
    tags = Keyword.get(opts, :tags, [])
    log_opts = Keyword.take(opts, [:api_key, :base_url])

    %{
      on_llm_token_usage: fn _chain, usage ->
        store_token_usage(usage)
      end,
      on_message_processed: fn chain, message ->
        log_processed_message(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_message_processing_error: fn chain, message ->
        log_error(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_tool_response_created: fn chain, message ->
        log_tool_response(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_retries_exceeded: fn chain ->
        log_retries_exceeded(project_id, chain, base_metadata, tags, log_opts)
      end
    }
  end

  @doc """
  Creates a streaming-aware callback handler.

  In addition to the standard handler callbacks, this tracks:

    * Time-to-first-token (TTFT) - Time from request start to first delta
    * Streaming duration - Total time for all deltas

  ## Usage

      handler = Braintrust.LangChainCallbacks.streaming_handler(
        project_id: "proj_xxx",
        tags: ["streaming"]
      )

      %{llm: ChatOpenAI.new!(%{model: "gpt-4", stream: true})}
      |> LLMChain.new!()
      |> LLMChain.add_callback(handler)
      |> LLMChain.run()

  """
  @spec streaming_handler(handler_opts()) :: map()
  def streaming_handler(opts) do
    base_handler = handler(opts)

    Map.merge(base_handler, %{
      on_llm_new_delta: fn _chain, deltas ->
        track_streaming_delta(deltas)
      end
    })
  end

  # Token usage storage (process dictionary)

  defp store_token_usage(usage) do
    Process.put(@token_usage_key, usage)
  end

  defp get_and_clear_token_usage do
    usage = Process.get(@token_usage_key)
    Process.delete(@token_usage_key)
    usage
  end

  # Logging functions

  defp log_processed_message(project_id, chain, message, base_metadata, tags, opts) do
    # Only log assistant messages (not user/system/tool)
    if message.role == :assistant do
      usage = get_and_clear_token_usage()
      streaming_metrics = get_and_clear_streaming_metrics()

      event = %{
        input: format_input(chain),
        output: format_output(message),
        metadata: build_metadata(chain, message, base_metadata),
        metrics: Map.merge(build_metrics(usage), streaming_metrics),
        tags: tags
      }

      Log.insert(project_id, [event], opts)
    end

    :ok
  end

  defp log_error(project_id, chain, message, base_metadata, tags, opts) do
    event = %{
      input: format_input(chain),
      output: format_output(message),
      error: "Message processing error",
      metadata:
        Map.merge(base_metadata, %{
          "error" => true,
          "status" => to_string(message.status),
          "model" => get_model_name(chain),
          "provider" => get_provider_name(chain)
        }),
      tags: ["error" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  defp log_tool_response(project_id, chain, message, base_metadata, tags, opts) do
    tool_results = message.tool_results || []

    event = %{
      input: format_tool_input(tool_results),
      output: format_output(message),
      metadata:
        Map.merge(base_metadata, %{
          "span_type" => "tool",
          "tool_count" => length(tool_results),
          "model" => get_model_name(chain),
          "provider" => get_provider_name(chain)
        }),
      tags: ["tool" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  defp log_retries_exceeded(project_id, chain, base_metadata, tags, opts) do
    event = %{
      input: format_input(chain),
      output: nil,
      error: "Max retries exceeded",
      metadata:
        Map.merge(base_metadata, %{
          "max_retry_count" => chain.max_retry_count,
          "failure_count" => chain.current_failure_count,
          "model" => get_model_name(chain),
          "provider" => get_provider_name(chain)
        }),
      tags: ["error", "retries_exceeded" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  # Input/Output formatting

  defp format_input(chain) do
    messages = chain.messages || []

    %{
      "messages" =>
        Enum.map(messages, fn msg ->
          %{
            "role" => to_string(msg.role),
            "content" => format_content(msg.content)
          }
        end)
    }
  end

  defp format_tool_input(tool_results) do
    %{
      "tool_results" =>
        Enum.map(tool_results, fn result ->
          %{
            "name" => result.name,
            "tool_call_id" => result.tool_call_id,
            "content" => format_content(result.content),
            "is_error" => result.is_error || false
          }
        end)
    }
  end

  defp format_output(message) do
    format_content(message.content)
  end

  defp format_content(content) when is_binary(content), do: content
  defp format_content(nil), do: nil
  defp format_content([]), do: nil

  defp format_content(content) when is_list(content) do
    # Handle ContentPart list - extract text parts
    content
    |> Enum.map(&format_content_part/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      [single] -> single
      multiple -> multiple
    end
  end

  defp format_content(other), do: inspect(other)

  defp format_content_part(%{type: :text, content: text}), do: text

  defp format_content_part(%{type: :text} = part),
    do: Map.get(part, :content) || Map.get(part, :text)

  defp format_content_part(%{type: type}),
    do: %{"type" => to_string(type), "content" => "[binary data]"}

  defp format_content_part(text) when is_binary(text), do: text
  defp format_content_part(_other), do: nil

  # Metadata building

  defp build_metadata(chain, message, base_metadata) do
    Map.merge(base_metadata, %{
      "model" => get_model_name(chain),
      "provider" => get_provider_name(chain),
      "status" => to_string(message.status),
      "has_tool_calls" => has_tool_calls?(message)
    })
  end

  defp has_tool_calls?(message) do
    case message.tool_calls do
      nil -> false
      [] -> false
      _tool_calls -> true
    end
  end

  # Metrics building

  defp build_metrics(nil), do: %{}

  defp build_metrics(usage) do
    %{
      "input_tokens" => usage.input,
      "output_tokens" => usage.output,
      "total_tokens" => total_tokens(usage)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp total_tokens(usage) do
    case {usage.input, usage.output} do
      {nil, nil} -> nil
      {input, nil} -> input
      {nil, output} -> output
      {input, output} -> input + output
    end
  end

  # Chain introspection

  defp get_model_name(chain) do
    case chain.llm do
      %{model: model} when is_binary(model) -> model
      _other -> "unknown"
    end
  end

  defp get_provider_name(chain) do
    chain.llm.__struct__
    |> Module.split()
    |> List.last()
    |> String.replace_leading("Chat", "")
    |> String.downcase()
  rescue
    _error -> "unknown"
  end

  # Streaming metrics tracking

  defp track_streaming_delta(deltas) when is_list(deltas) do
    now = System.monotonic_time(:millisecond)

    # Record request start on first delta batch
    if is_nil(Process.get(@request_start_key)) do
      Process.put(@request_start_key, now)
    end

    # Record first token time
    if is_nil(Process.get(@first_token_time_key)) and has_content?(deltas) do
      Process.put(@first_token_time_key, now)
    end
  end

  defp has_content?(deltas) do
    Enum.any?(deltas, fn delta ->
      delta.content != nil and delta.content != "" and delta.content != []
    end)
  end

  defp get_and_clear_streaming_metrics do
    request_start = Process.get(@request_start_key)
    first_token_time = Process.get(@first_token_time_key)

    Process.delete(@request_start_key)
    Process.delete(@first_token_time_key)

    now = System.monotonic_time(:millisecond)

    metrics = %{}

    metrics =
      if first_token_time && request_start do
        Map.put(metrics, "time_to_first_token_ms", first_token_time - request_start)
      else
        metrics
      end

    metrics =
      if request_start do
        Map.put(metrics, "streaming_duration_ms", now - request_start)
      else
        metrics
      end

    metrics
  end
end
