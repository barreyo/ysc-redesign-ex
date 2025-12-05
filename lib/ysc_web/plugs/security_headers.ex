defmodule YscWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Sets security headers including CSP with nonce support.
  This plug should be called after CSPNonce plug to ensure the nonce is available.
  """
  import Plug.Conn
  alias Ysc.S3Config

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = conn.assigns[:csp_nonce] || ""

    # Check if we're in development mode
    # In production, Mix.env() is not available, so we check the application env
    is_dev =
      case Application.get_env(:ysc, :environment) do
        :dev ->
          true

        _ ->
          # Fallback: check if code_reloading is enabled (dev only)
          Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] == true
      end

    # Get S3 storage URLs for image sources
    s3_image_sources = get_s3_image_sources()

    # Get S3 storage URLs for connect sources (for uploads)
    s3_connect_sources = get_s3_connect_sources()

    # Build CSP policy with nonce
    csp_policy = build_csp_policy(nonce, is_dev, s3_image_sources, s3_connect_sources)

    conn
    |> put_resp_header("content-security-policy", csp_policy)
    |> put_resp_header(
      "permissions-policy",
      # Allow payment for Stripe, block other features
      "camera=(), microphone=(), geolocation=(), payment=(self \"https://js.stripe.com\"), usb=(), magnetometer=(), gyroscope=()"
    )
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-resource-policy", "same-origin")
    |> put_resp_header("cross-origin-embedder-policy", "unsafe-none")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_hsts_header(is_dev)
  end

  defp build_csp_policy(nonce, is_dev, s3_image_sources, s3_connect_sources) do
    # Base sources
    default_src = "'self'"

    # Script sources - allow self, nonce, and external CDNs
    script_src =
      [
        "'self'",
        "'nonce-#{nonce}'",
        "https://js.stripe.com",
        "https://js.radar.com",
        "https://cdn.jsdelivr.net",
        "https://unpkg.com",
        # Cloudflare Turnstile
        "https://challenges.cloudflare.com"
      ]
      |> Enum.join(" ")

    # Style sources - allow self, unsafe-inline, and external CDNs
    # Note: Nonces don't work for style attributes (style="..."), only for <style> tags.
    # When nonce is present, 'unsafe-inline' is ignored, so we remove nonce from style-src.
    # We use 'unsafe-inline' which covers both <style> tags and style attributes.
    style_src =
      [
        "'self'",
        # Required for inline style attributes and <style> tags
        "'unsafe-inline'",
        "https://js.radar.com",
        "https://unpkg.com"
      ]
      |> Enum.join(" ")

    # Connect sources - allow WebSockets for LiveView
    # In dev, allow both ws: and wss:, in prod only wss:
    # Also allow jsdelivr for source maps, Radar API, and S3 storage for uploads
    base_connect_sources =
      if is_dev do
        [
          "'self'",
          "ws:",
          "wss:",
          "https://js.stripe.com",
          "https://challenges.cloudflare.com",
          "https://cdn.jsdelivr.net",
          "https://api.radar.io"
        ]
      else
        [
          "'self'",
          "wss:",
          "https://js.stripe.com",
          "https://challenges.cloudflare.com",
          "https://cdn.jsdelivr.net",
          "https://api.radar.io"
        ]
      end

    connect_src = (base_connect_sources ++ s3_connect_sources) |> Enum.join(" ")

    # Image sources - include S3 storage domains
    # Allow all HTTPS images (covers production S3)
    img_src =
      ([
         "'self'",
         "data:",
         "blob:",
         "https:"
       ] ++ s3_image_sources)
      |> Enum.join(" ")

    # Font sources - allow Radar fonts
    font_src =
      [
        "'self'",
        "data:",
        # Radar library loads fonts from radar.com
        "https://radar.com"
      ]
      |> Enum.join(" ")

    # Frame sources - allow Stripe, Cloudflare Turnstile, and Phoenix Live Reload (dev only)
    frame_src =
      if is_dev do
        "'self' https://js.stripe.com https://challenges.cloudflare.com"
      else
        "https://js.stripe.com https://challenges.cloudflare.com"
      end

    # Worker sources - allow blob: workers (Radar library creates workers from blob URLs)
    worker_src = "'self' blob:"

    # Object sources - deny by default
    object_src = "'none'"

    # Base URI
    base_uri = "'self'"

    # Form action - allow self and Stripe
    form_action = "'self' https://js.stripe.com"

    # Frame ancestors - deny embedding
    frame_ancestors = "'none'"

    # Upgrade insecure requests
    upgrade_insecure_requests = "upgrade-insecure-requests"

    [
      "default-src #{default_src}",
      "script-src #{script_src}",
      "style-src #{style_src}",
      "connect-src #{connect_src}",
      "img-src #{img_src}",
      "font-src #{font_src}",
      "frame-src #{frame_src}",
      "worker-src #{worker_src}",
      "object-src #{object_src}",
      "base-uri #{base_uri}",
      "form-action #{form_action}",
      "frame-ancestors #{frame_ancestors}",
      upgrade_insecure_requests
    ]
    |> Enum.join("; ")
  end

  # Get S3 storage URLs that should be allowed for connect operations (uploads)
  defp get_s3_connect_sources do
    base_url = S3Config.base_url()
    sources = []

    # Add the base URL if it's set
    sources =
      if base_url && base_url != "" do
        # Extract the hostname from the URL
        case URI.parse(base_url) do
          %URI{scheme: scheme, host: host, port: port} when not is_nil(host) ->
            # Build the source string
            source =
              case {scheme, port} do
                {"http", 4566} ->
                  # Localstack dev: http://media.s3.localhost.localstack.cloud:4566
                  "#{scheme}://#{host}:#{port}"

                {"https", nil} ->
                  # Production Tigris: https://*.fly.storage.tigris.dev
                  if String.contains?(host, "tigris.dev") do
                    # Allow all Tigris subdomains for different buckets
                    "https://*.fly.storage.tigris.dev"
                  else
                    "#{scheme}://#{host}"
                  end

                {scheme, nil} when scheme in ["http", "https"] ->
                  "#{scheme}://#{host}"

                {scheme, port} when scheme in ["http", "https"] and not is_nil(port) ->
                  "#{scheme}://#{host}:#{port}"

                _ ->
                  nil
              end

            if source, do: [source | sources], else: sources

          _ ->
            sources
        end
      else
        sources
      end

    # Always allow Tigris production domains (wildcard for all buckets)
    # This covers all bucket subdomains like ysc-sandbox-media.fly.storage.tigris.dev
    sources =
      ["https://*.fly.storage.tigris.dev" | sources]
      |> Enum.uniq()

    # Also allow HTTP for local development (localstack with specific port)
    sources =
      if Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] == true do
        ["http://*.localhost.localstack.cloud:4566" | sources]
      else
        sources
      end

    Enum.uniq(sources)
  end

  # Get S3 storage URLs that should be allowed for images
  defp get_s3_image_sources do
    base_url = S3Config.base_url()
    sources = []

    # Add the base URL if it's set
    sources =
      if base_url && base_url != "" do
        # Extract the hostname from the URL
        case URI.parse(base_url) do
          %URI{scheme: scheme, host: host, port: port} when not is_nil(host) ->
            # Build the source string
            source =
              case {scheme, port} do
                {"http", 4566} ->
                  # Localstack dev: http://media.s3.localhost.localstack.cloud:4566
                  # CSP doesn't support port wildcards, so we need to specify the exact port
                  "#{scheme}://#{host}:#{port}"

                {"https", nil} ->
                  # Production Tigris: https://*.fly.storage.tigris.dev
                  if String.contains?(host, "tigris.dev") do
                    # Allow all Tigris subdomains for different buckets
                    "https://*.fly.storage.tigris.dev"
                  else
                    "#{scheme}://#{host}"
                  end

                {scheme, nil} when scheme in ["http", "https"] ->
                  "#{scheme}://#{host}"

                {scheme, port} when scheme in ["http", "https"] and not is_nil(port) ->
                  "#{scheme}://#{host}:#{port}"

                _ ->
                  nil
              end

            if source, do: [source | sources], else: sources

          _ ->
            sources
        end
      else
        sources
      end

    # Always allow Tigris production domains (wildcard for all buckets)
    # This covers all bucket subdomains like ysc-sandbox-media.fly.storage.tigris.dev
    sources =
      ["https://*.fly.storage.tigris.dev" | sources]
      |> Enum.uniq()

    # Also allow HTTP for local development (localstack with specific port)
    # CSP doesn't support port wildcards, so we specify the exact port
    sources =
      if Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] == true do
        ["http://*.localhost.localstack.cloud:4566" | sources]
      else
        sources
      end

    Enum.uniq(sources)
  end

  # Set HSTS header only on HTTPS connections and only in production
  defp put_hsts_header(conn, is_dev) do
    # Only set HSTS in production (not in development)
    # HSTS should only be set on HTTPS connections
    if not is_dev do
      # Check if the connection is HTTPS (either directly or via proxy)
      is_https =
        case get_req_header(conn, "x-forwarded-proto") do
          ["https"] -> true
          _ -> conn.scheme == :https
        end

      if is_https do
        # Set HSTS with 1 year max-age and includeSubDomains
        # max-age: 31,536,000 seconds = 1 year
        # includeSubDomains: Apply to all subdomains
        put_resp_header(
          conn,
          "strict-transport-security",
          "max-age=31536000; includeSubDomains"
        )
      else
        conn
      end
    else
      # Don't set HSTS in development to avoid browser caching issues
      conn
    end
  end
end
