//
//  ContentView.swift
//  Ysc
//

import LiveViewNative
import LiveViewNativeLiveForm
import SwiftUI

@available(iOS 18.0, *)
struct ContentView: View {
    @State private var isAuthenticated: Bool = false
    @State private var apiKey: String?
    @StateObject private var inactivityTimer = InactivityTimer()

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
                apiKey: apiKey,
                inactivityTimer: inactivityTimer
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
@available(iOS 18.0, *)
struct LiveViewWithAPIKey: View {
    let baseDevelopmentURL: URL
    let baseProductionURL: URL
    let apiKey: String
    @ObservedObject var inactivityTimer: InactivityTimer
    @State private var forceNavigateToHome: Bool = false
    @State private var navigationKey: Int = 0
    @State private var isOnHomePage: Bool = true // Track if we're on home page
    @State private var justRedirected: Bool = false // Track if we just redirected (don't show countdown/redirect again)
    @State private var initialLoadComplete: Bool = false // Track if initial load is complete

    init(developmentURL: URL, productionURL: URL, apiKey: String, inactivityTimer: InactivityTimer) {
        self.baseDevelopmentURL = developmentURL
        self.baseProductionURL = productionURL
        self.apiKey = apiKey
        self._inactivityTimer = ObservedObject(wrappedValue: inactivityTimer)
    }

    private func urlWithAPIKey(_ baseURL: URL, path: String? = nil) -> URL {
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        // Set path if provided (for navigation to home)
        if let path = path {
            urlComponents.path = path
        }
        // Append API key as query parameter
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        urlComponents.queryItems = queryItems
        return urlComponents.url ?? baseURL
    }

    private var developmentURLWithKey: URL {
        // If we need to navigate to home, use home path, otherwise use base URL
        let url = urlWithAPIKey(baseDevelopmentURL, path: forceNavigateToHome ? "/" : nil)
        print("[ContentView] developmentURLWithKey computed - path: \(url.path), forceNavigateToHome: \(forceNavigateToHome)")
        return url
    }

    private var productionURLWithKey: URL {
        let url = urlWithAPIKey(baseProductionURL, path: forceNavigateToHome ? "/" : nil)
        print("[ContentView] productionURLWithKey computed - path: \(url.path), forceNavigateToHome: \(forceNavigateToHome)")
        return url
    }

    var body: some View {
        ZStack {
            #LiveView(
                .automatic(
                    development: developmentURLWithKey,
                    production: productionURLWithKey
                ),
                addons: [.liveForm, .roomCalendarView, .cabinRulesView, .pathTrackerView]
            ) {
                ConnectingView()
            } disconnected: {
                DisconnectedView()
            } reconnecting: { content, isReconnecting in
                ReconnectingView(isReconnecting: isReconnecting) {
                    content
                        .detectInactivity(timer: inactivityTimer)
                        .onAppear {
                            // Set up timeout callback to navigate to home
                            setupInactivityHandler()
                        }
                }
                .onAppear {
                    // When reconnecting view appears after initial load, it means we've navigated
                    // Reset the inactivity timer when navigation happens
                    if initialLoadComplete && !forceNavigateToHome {
                        // User navigated to a new page - reset timer and mark as not on home
                        isOnHomePage = false
                        justRedirected = false // Reset redirect flag on new navigation
                        inactivityTimer.reset()
                        print("[ContentView] Navigation detected - reset timer, isOnHomePage = false")
                    } else if forceNavigateToHome {
                        // We're forcing to home - mark as on home and reset redirect flag
                        isOnHomePage = true
                        justRedirected = true // Set flag so we don't show countdown/redirect again
                        inactivityTimer.reset()
                        print("[ContentView] Forced to home - isOnHomePage = true, justRedirected = true")
                    }
                }
            } error: { error in
                ErrorView(error: error)
            }
            .detectInactivity(timer: inactivityTimer)
            .onAppear {
                // Set up timeout callback to navigate to home
                setupInactivityHandler()

                // Track initial load - on first appearance, we're on home
                if !initialLoadComplete {
                    initialLoadComplete = true
                    isOnHomePage = true
                    justRedirected = false
                    inactivityTimer.reset()
                    print("[ContentView] Initial load - on home page, reset timer")
                }
            }
            .onChange(of: forceNavigateToHome) { isForcing in
                // When we force navigate to home, mark as on home
                if isForcing {
                    isOnHomePage = true
                    justRedirected = true
                }
            }
            .id(navigationKey) // Force re-render when navigation key changes

            // Countdown indicator overlay (only show if not on home page and not just redirected)
            let shouldShowCountdown = !isOnHomePage &&
                !justRedirected && // Don't show if we just redirected
                !forceNavigateToHome && // Don't show when navigating to home
                ((inactivityTimer.secondsRemaining <= InactivityTimer.warningThreshold && inactivityTimer.secondsRemaining > 0) || inactivityTimer.isCancelling)

            if shouldShowCountdown {
                InactivityCountdownView(
                    secondsRemaining: Int(inactivityTimer.secondsRemaining),
                    isCancelling: inactivityTimer.isCancelling
                )
            }
        }
    }

    private func setupInactivityHandler() {
        inactivityTimer.onTimeout = {
            // Only navigate if we're not on home page and haven't just redirected
            if !isOnHomePage && !justRedirected {
                print("[ContentView] Inactivity timeout - navigating to home")
                // Force navigation by changing the URL to home and triggering a re-render
                DispatchQueue.main.async {
                    forceNavigateToHome = true
                    isOnHomePage = true
                    justRedirected = true // Set flag so we don't show countdown/redirect again
                    navigationKey += 1 // Force LiveView to reconnect with home URL
                    // Reset the flag after a short delay so normal navigation can work again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        forceNavigateToHome = false
                    }
                }
            } else {
                print("[ContentView] Inactivity timeout - already on home or just redirected, skipping navigation")
            }
        }
    }
}

