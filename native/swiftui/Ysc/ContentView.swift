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
struct LiveViewWithAPIKey: View {
    let baseDevelopmentURL: URL
    let baseProductionURL: URL
    let apiKey: String
    @ObservedObject var inactivityTimer: InactivityTimer
    @State private var forceNavigateToHome: Bool = false
    @State private var navigationKey: Int = 0
    @State private var hasNavigatedAway: Bool = false // Track if user has navigated away from home
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
        urlWithAPIKey(baseDevelopmentURL, path: forceNavigateToHome ? "/" : nil)
    }

    private var productionURLWithKey: URL {
        urlWithAPIKey(baseProductionURL, path: forceNavigateToHome ? "/" : nil)
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
                    // When reconnecting view appears, if we're not forcing navigation to home,
                    // assume we've navigated to a new route
                    if initialLoadComplete && !forceNavigateToHome {
                        hasNavigatedAway = true
                        print("[ContentView] Reconnecting view appeared - not forcing to home, setting hasNavigatedAway = true")
                    }
                }
            } error: { error in
                ErrorView(error: error)
            }
            .detectInactivity(timer: inactivityTimer)
            .onAppear {
                // Set up timeout callback to navigate to home (also set up here for initial load)
                setupInactivityHandler()
                // Listen for navigation events to track if we're on home page
                setupNavigationTracking()

                // Track initial load - on first appearance, we're on home
                if !initialLoadComplete {
                    initialLoadComplete = true
                    hasNavigatedAway = false
                    print("[ContentView] Initial load - on home page (hasNavigatedAway = false)")
                } else {
                    // After initial load, if view appears and we're not forcing navigation to home,
                    // it means we've navigated to a different page (LiveView reconnected to a new route)
                    // Set hasNavigatedAway = true to ensure countdown works on non-home pages
                    if !forceNavigateToHome {
                        hasNavigatedAway = true
                        print("[ContentView] View appeared after initial load - not forcing to home, setting hasNavigatedAway = true")
                    } else {
                        hasNavigatedAway = false
                        print("[ContentView] View appeared - forcing navigation to home (hasNavigatedAway = false)")
                    }
                }
            }
            .onDisappear {
                // When view disappears, if we're not forcing navigation to home,
                // it likely means we're navigating to a new route
                // Set hasNavigatedAway = true to prepare for the next route
                if !forceNavigateToHome && initialLoadComplete {
                    hasNavigatedAway = true
                    print("[ContentView] View disappeared - not forcing to home, setting hasNavigatedAway = true for next route")
                }
            }
            .onChange(of: navigationKey) { newKey in
                // When navigation key changes, check if we're forcing navigation to home
                if forceNavigateToHome {
                    hasNavigatedAway = false
                    print("[ContentView] Navigation key changed - forcing to home (hasNavigatedAway = false)")
                } else if initialLoadComplete {
                    // If navigation key changes and we're not forcing to home, we've navigated away
                    // This is the most reliable indicator of navigation
                    hasNavigatedAway = true
                    print("[ContentView] Navigation key changed - not forcing to home, setting hasNavigatedAway = true")
                }
            }
            .onChange(of: forceNavigateToHome) { isForcing in
                // When we force navigate to home, we're definitely on home
                if isForcing {
                    hasNavigatedAway = false
                    print("[ContentView] Force navigate to home changed - setting hasNavigatedAway = false")
                }
            }
            .id(navigationKey) // Force re-render when navigation key changes
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CurrentPathChanged"))) { notification in
                if let path = notification.userInfo?["path"] as? String {
                    let isHome = path == "/" || path.isEmpty
                    hasNavigatedAway = !isHome
                    print("[ContentView] Path changed to '\(path)' - hasNavigatedAway = \(hasNavigatedAway)")
                }
            }
            .onChange(of: inactivityTimer.secondsRemaining) { secondsRemaining in
                // Debug logging for countdown visibility
                if secondsRemaining <= InactivityTimer.warningThreshold && secondsRemaining > 0 {
                    let shouldShow = hasNavigatedAway && !forceNavigateToHome && (secondsRemaining > 0 || inactivityTimer.isCancelling)
                    print("[ContentView] Countdown check - hasNavigatedAway: \(hasNavigatedAway), forceNavigateToHome: \(forceNavigateToHome), shouldShow: \(shouldShow), secondsRemaining: \(secondsRemaining)")
                }
            }

            // Countdown indicator overlay (only show if not on home page)
            // Only show countdown if we've explicitly navigated away (hasNavigatedAway = true)
            // We don't use the conservative fallback here because we want to avoid showing
            // the countdown on the home page. The timeout handler uses the conservative
            // check, but the countdown visibility should be more strict.
            let shouldShowCountdown = hasNavigatedAway &&
                !forceNavigateToHome && // Don't show when navigating to home
                ((inactivityTimer.secondsRemaining <= InactivityTimer.warningThreshold && inactivityTimer.secondsRemaining > 0) || inactivityTimer.isCancelling)

            if shouldShowCountdown {
                InactivityCountdownView(
                    secondsRemaining: Int(inactivityTimer.secondsRemaining),
                    isCancelling: inactivityTimer.isCancelling
                )
            }
        }
        .onChange(of: inactivityTimer.secondsRemaining) { secondsRemaining in
            // Debug logging for countdown visibility
            if secondsRemaining <= InactivityTimer.warningThreshold && secondsRemaining > 0 {
                let shouldShow = hasNavigatedAway && !forceNavigateToHome && (secondsRemaining > 0 || inactivityTimer.isCancelling)
                print("[ContentView] Countdown check - hasNavigatedAway: \(hasNavigatedAway), forceNavigateToHome: \(forceNavigateToHome), shouldShow: \(shouldShow), secondsRemaining: \(secondsRemaining)")
            }
        }
    }

    private func setupInactivityHandler() {
        inactivityTimer.onTimeout = {
            // Only navigate if user has explicitly navigated away from home
            // Don't use conservative check here - we don't want to redirect on home page
            print("[ContentView] Inactivity timeout triggered - hasNavigatedAway = \(hasNavigatedAway), initialLoadComplete = \(initialLoadComplete)")

            if hasNavigatedAway {
                print("[ContentView] Inactivity timeout triggered - navigating to home")
                // Force navigation by changing the URL to home and triggering a re-render
                DispatchQueue.main.async {
                    forceNavigateToHome = true
                    hasNavigatedAway = false // Reset - we're back on home
                    navigationKey += 1 // Force LiveView to reconnect with home URL
                    // Reset the flag after a short delay so normal navigation can work again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        forceNavigateToHome = false
                    }
                }
            } else {
                print("[ContentView] Inactivity timeout triggered - already on home page, skipping navigation")
            }
        }
    }

    private func setupNavigationTracking() {
        // Since we can't easily receive push_events in SwiftUI, we use a heuristic:
        // We track navigation by assuming we've navigated away unless we explicitly
        // navigate to home via timeout. This means:
        // - On initial load, we start with hasNavigatedAway = false (we're on home)
        // - After a short delay, if we haven't navigated to home, set hasNavigatedAway = true
        // - When we navigate to home via timeout, set hasNavigatedAway = false
        // This is handled in onAppear and onChange handlers
    }
}

