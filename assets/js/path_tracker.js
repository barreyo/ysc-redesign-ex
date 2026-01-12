// PathTracker hook - listens for current_path push_events and posts to NotificationCenter
// This is used by the native SwiftUI app to track the current route
let PathTracker = {
    mounted() {
        // Listen for push_event("current_path") from LiveView
        this.handleEvent("current_path", ({ path }) => {
            // Post notification that SwiftUI can listen to
            // For native apps, this will be handled differently
            // For now, we'll use a custom event that can be picked up
            window.dispatchEvent(
                new CustomEvent("liveview:current_path", {
                    detail: { path }
                })
            );
        });
    }
};