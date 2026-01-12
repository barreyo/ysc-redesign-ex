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
        // Hidden component - just a minimal view that doesn't access any LiveView internals
        // Path tracking is handled by backend push_events via handle_params
        // This component exists in the template but doesn't need to do anything
        EmptyView()
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
