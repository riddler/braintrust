defmodule Braintrust.Resource do
  @moduledoc false
  # Internal helper module for common resource operations.
  # Not part of the public API.

  alias Braintrust.Client

  @doc false
  @spec list_all(String.t(), keyword(), (map() -> struct())) ::
          {:ok, [struct()]} | {:error, Braintrust.Error.t()}
  def list_all(api_path, opts, to_struct_fn) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    {pagination_opts, filter_params} = split_pagination_opts(query_opts)
    params = build_filter_params(filter_params, opts)

    get_all_opts = Keyword.merge(pagination_opts, params: params)

    case Client.get_all(client, api_path, get_all_opts) do
      {:ok, items} -> {:ok, Enum.map(items, to_struct_fn)}
      {:error, error} -> {:error, error}
    end
  end

  @doc false
  @spec stream_all(String.t(), keyword(), (map() -> struct())) :: Enumerable.t()
  def stream_all(api_path, opts, to_struct_fn) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    {pagination_opts, filter_params} = split_pagination_opts(query_opts)
    params = build_filter_params(filter_params, opts)

    get_stream_opts = Keyword.merge(pagination_opts, params: params)

    client
    |> Client.get_stream(api_path, get_stream_opts)
    |> Stream.map(to_struct_fn)
  end

  @doc false
  @spec split_opts(keyword()) :: {keyword(), keyword()}
  def split_opts(opts) do
    Keyword.split(opts, [:api_key, :base_url, :timeout, :max_retries])
  end

  @doc false
  @spec split_pagination_opts(keyword()) :: {keyword(), keyword()}
  def split_pagination_opts(opts) do
    Keyword.split(opts, [:limit, :starting_after, :ending_before])
  end

  @doc false
  @spec build_filter_params(keyword(), keyword()) :: keyword()
  def build_filter_params(filter_params, all_opts) do
    []
    |> maybe_add(:project_id, filter_params[:project_id])
    |> maybe_add(:project_name, filter_params[:project_name])
    |> maybe_add(:experiment_name, filter_params[:experiment_name])
    |> maybe_add(:org_name, filter_params[:org_name])
    |> maybe_add(:ids, filter_params[:ids])
    # Support all possible filter keys from all_opts if not in filter_params
    |> maybe_add(:project_id, all_opts[:project_id])
    |> maybe_add(:project_name, all_opts[:project_name])
    |> maybe_add(:experiment_name, all_opts[:experiment_name])
    |> maybe_add(:org_name, all_opts[:org_name])
    |> Enum.uniq_by(fn {key, _value} -> key end)
  end

  @doc false
  @spec maybe_add(keyword(), atom(), any()) :: keyword()
  def maybe_add(params, _key, nil), do: params
  def maybe_add(params, key, value), do: Keyword.put(params, key, value)
end
