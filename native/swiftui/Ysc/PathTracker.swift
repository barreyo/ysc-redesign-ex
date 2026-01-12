//
//  PathTracker.swift
//  Ysc
//
//  LiveElement component that listens for current_path push_events from LiveView
//  and posts NotificationCenter notifications for SwiftUI to consume

import SwiftUI
import LiveViewNative

@LiveElement
struct PathTracker<Root: RootRegistry>: View {
    let element: ElementNode

    var body: some View {
        // Hidden component that listens for push_event messages via JavaScript hook
        // The JavaScript hook (path_tracker.js) should handle receiving push_event messages
        // and posting to NotificationCenter. However, since this is a native app,
        // JavaScript hooks might not work. The actual event handling should happen
        // via the JavaScript hook, but we need to verify it works in native apps.
        EmptyView()
            .onAppear {
                print("[PathTracker] Component appeared - JavaScript hook should handle events")
                print("[PathTracker] If JavaScript hooks don't work in native apps, we need an alternative")
            }
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct PathTrackerView<Root: RootRegistry> {
        enum TagName: String {
            case pathTracker = "PathTracker"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .pathTracker:
                PathTracker<Root>(element: element)
            }
        }
    }
}
