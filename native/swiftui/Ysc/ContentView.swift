//
//  ContentView.swift
//  Ysc
//

import SwiftUI

import LiveViewNative
import LiveViewNativeLiveForm


struct ContentView: View {
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

    var body: some View {
                #LiveView(
                    .automatic(
                        development: Self.developmentURL(),
                        production: URL(string: "https://example.com/")!
                    ),
                    addons: [.liveForm]
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
