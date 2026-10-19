import SwiftUI

@main
struct ShineApp: App {
    var body: some Scene {
        WindowGroup {
            // The site ships its own light and dark themes, toggles between them
            // with a class, and remembers the choice in localStorage. Nothing is
            // forced here on purpose: pinning the scheme would override
            // prefers-color-scheme and fight the site's own styling.
            ContentView()
        }
    }
}
