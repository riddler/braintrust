defmodule Braintrust.ErrorTest do
  use ExUnit.Case, async: true
  doctest Braintrust.Error

  alias Braintrust.Error

  describe "new/3" do
    test "creates error with required fields" do
      error = Error.new(:not_found, "Resource not found")

      assert error.type == :not_found
      assert error.message == "Resource not found"
      assert error.code == nil
      assert error.status == nil
      assert error.retry_after == nil
    end

    test "creates error with optional fields" do
      error =
        Error.new(:rate_limit, "Too many requests",
          status: 429,
          code: "rate_limit_exceeded",
          retry_after: 5000
        )

      assert error.type == :rate_limit
      assert error.message == "Too many requests"
      assert error.status == 429
      assert error.code == "rate_limit_exceeded"
      assert error.retry_after == 5000
    end
  end

  describe "retryable?/1" do
    test "returns true for retryable error types" do
      assert Error.retryable?(Error.new(:conflict, "Conflict"))
      assert Error.retryable?(Error.new(:rate_limit, "Rate limited"))
      assert Error.retryable?(Error.new(:server_error, "Server error"))
      assert Error.retryable?(Error.new(:timeout, "Timeout"))
      assert Error.retryable?(Error.new(:connection, "Connection error"))
    end

    test "returns false for non-retryable error types" do
      refute Error.retryable?(Error.new(:bad_request, "Bad request"))
      refute Error.retryable?(Error.new(:authentication, "Unauthorized"))
      refute Error.retryable?(Error.new(:permission_denied, "Forbidden"))
      refute Error.retryable?(Error.new(:not_found, "Not found"))
      refute Error.retryable?(Error.new(:unprocessable_entity, "Invalid"))
    end
  end

  describe "type_from_status/1" do
    test "maps HTTP status codes to error types" do
      assert Error.type_from_status(400) == :bad_request
      assert Error.type_from_status(401) == :authentication
      assert Error.type_from_status(403) == :permission_denied
      assert Error.type_from_status(404) == :not_found
      assert Error.type_from_status(409) == :conflict
      assert Error.type_from_status(422) == :unprocessable_entity
      assert Error.type_from_status(429) == :rate_limit
      assert Error.type_from_status(500) == :server_error
      assert Error.type_from_status(502) == :server_error
      assert Error.type_from_status(503) == :server_error
    end

    test "maps unknown 4xx to bad_request" do
      assert Error.type_from_status(418) == :bad_request
    end
  end
end
