defmodule Ysc.S3Config do
  @moduledoc """
  Centralized S3 configuration for different environments.
  Provides environment-specific S3 bucket names, URLs, and AWS regions.
  """

  @doc """
  Returns the S3 bucket name for the current environment.
  """
  def bucket_name do
    Application.get_env(:ysc, :s3_bucket, "media")
  end

  @doc """
  Returns the S3 base URL for the current environment.
  For localstack: http://media.s3.localhost.localstack.cloud:4566
  For production: Uses the configured S3 endpoint URL or constructs from bucket and region
  """
  def base_url do
    case Application.get_env(:ysc, :s3_base_url) do
      nil ->
        default = default_base_url()
        # If default is nil (production), construct from bucket and region
        if default == nil do
          bucket = bucket_name()
          region = region()
          "https://#{bucket}.s3.#{region}.amazonaws.com"
        else
          default
        end

      url ->
        url
    end
  end

  @doc """
  Returns the AWS region for S3 operations.
  """
  def region do
    Application.get_env(:ysc, :s3_region, "us-west-1")
  end

  @doc """
  Returns the S3 endpoint configuration for ExAws.
  """
  def endpoint_config do
    case Application.get_env(:ysc, :s3_endpoint) do
      nil -> []
      endpoint_config -> endpoint_config
    end
  end

  @doc """
  Constructs the full URL for an S3 object given a key.
  This is used for constructing the final object URL after upload.
  """
  def object_url(key) do
    base = base_url()
    bucket = bucket_name()

    case base do
      url when is_binary(url) and url != "" ->
        # Localstack or custom endpoint
        base_url = String.trim_trailing(base, "/")
        key = String.trim_leading(key, "/")
        "#{base_url}/#{bucket}/#{key}"

      _ ->
        # Production AWS S3 - construct from bucket and region
        region = region()
        key = String.trim_leading(key, "/")
        "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
    end
  end

  defp default_base_url do
    env =
      Application.get_env(:ysc, :env) ||
        if function_exported?(Mix, :env, 0), do: Mix.env(), else: :prod

    case env do
      :dev ->
        "http://media.s3.localhost.localstack.cloud:4566"

      :test ->
        "http://media.s3.localhost.localstack.cloud:4566"

      _ ->
        # Production - will be configured via runtime.exs or constructed from bucket/region
        nil
    end
  end
end
