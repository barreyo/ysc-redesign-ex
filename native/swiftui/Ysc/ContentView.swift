//
//  ContentView.swift
//  Ysc
//

import LiveViewNative
import LiveViewNativeLiveForm
import SwiftUI

struct ContentView: View {
    @State private var isAuthenticated: Bool = false
    @State private var apiKey: String?

    private static func developmentURL() -> URL {
        // `.localhost(...)` resolves to `localhost` which often prefers IPv6 (`::1`).
        // Our Phoenix dev server is commonly bound on IPv4 only, which can lead to
        // `nw_socket_handle_socket_event ... ::1.4000 ... Connection refused`.
        //
        // Override in Xcode Scheme (Run > Arguments > Environment Variables):
        // - LVN_DEV_HOST (e.g. 127.0.0.1 for Simulator, or your Mac LAN IP for devices)
        // - LVN_DEV_PORT (defaults to 4000)
        let host = ProcessInfo.processInfo.environment["LVN_DEV_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["LVN_DEV_PORT"] ?? "4000"
        return URL(string: "http://\(host):\(port)/")!
    }

    init() {
        // Check if API key exists on initialization
        _isAuthenticated = State(initialValue: APIKeyManager.hasAPIKey())
        _apiKey = State(initialValue: APIKeyManager.getAPIKey())
    }

    var body: some View {
        if isAuthenticated, let apiKey = apiKey {
            // Show LiveView with API key in URL query parameter
            LiveViewWithAPIKey(
                developmentURL: Self.developmentURL(),
                productionURL: URL(string: "https://example.com/")!,
                apiKey: apiKey
            )
        } else {
            // Show API key input view
            APIKeyInputView(isAuthenticated: $isAuthenticated)
                .onChange(of: isAuthenticated) { newValue in
                    if newValue {
                        // Reload API key when authenticated
                        apiKey = APIKeyManager.getAPIKey()
                    }
                }
        }
    }
}

// Helper view that configures LiveView with API key in URL query parameter
struct LiveViewWithAPIKey: View {
    let developmentURLWithKey: URL
    let productionURLWithKey: URL

    init(developmentURL: URL, productionURL: URL, apiKey: String) {
        // Append API key as query parameter
        // Note: LiveView Native doesn't expose a direct way to set custom headers.
        // We use query parameters as a workaround. The backend accepts API key from
        // both X-API-Key header and api_key query param.
        func urlWithAPIKey(_ baseURL: URL) -> URL {
            guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return baseURL
            }
            var queryItems = urlComponents.queryItems ?? []
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            urlComponents.queryItems = queryItems
            return urlComponents.url ?? baseURL
        }

        self.developmentURLWithKey = urlWithAPIKey(developmentURL)
        self.productionURLWithKey = urlWithAPIKey(productionURL)
    }

    var body: some View {
        #LiveView(
            .automatic(
                development: developmentURLWithKey,
                production: productionURLWithKey
            ),
            addons: [.liveForm, .roomCalendarView]
        ) {
            ConnectingView()
        } disconnected: {
            DisconnectedView()
        } reconnecting: { content, isReconnecting in
            ReconnectingView(isReconnecting: isReconnecting) {
                content
            }
        } error: { error in
            ErrorView(error: error)
        }
    }
}

