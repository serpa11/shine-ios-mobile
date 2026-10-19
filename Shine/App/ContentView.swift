import SwiftUI

struct ContentView: View {
    @State private var isRefreshing = false
    @State private var loadError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            ShineWebView(isRefreshing: $isRefreshing, loadError: $loadError)
                .ignoresSafeArea()
                .background(Color.black)

            if let loadError {
                LoadErrorBanner(message: loadError) { self.loadError = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: loadError)
    }
}

/// Shown only when a load actually fails. The site has no offline page of its
/// own, so without this the app would just sit on a black screen.
private struct LoadErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach Shine")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Retry") {
                onDismiss()
                NotificationCenter.default.post(name: .shineReload, object: nil)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.25))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }
}

extension Notification.Name {
    static let shineReload = Notification.Name("shine.reload")
}
