import SwiftUI
import SwiftData

@main
struct TuberApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in Deeplink.handle(url) }
        }
        .modelContainer(Persistence.container)
        .onChange(of: scenePhase) { _, phase in
            PlayerModel.shared.inBackground = phase == .background
            if phase == .active {
                Persistence.dedupe()
                Deeplink.consumePending()
            }
        }
    }
}

@MainActor
enum Deeplink {
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TuberAppGroup") as? String ?? ""
    static let pendingKey = "pendingVideoID"

    /// tuber://play?v=ID
    static func handle(_ url: URL) {
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            ?? VideoLink.videoID(from: url)
        if let id, VideoLink.isValidID(id) { open(id) }
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: pendingKey)
    }

    static func consumePending() {
        let defaults = UserDefaults(suiteName: appGroup)
        guard let id = defaults?.string(forKey: pendingKey), VideoLink.isValidID(id) else { return }
        defaults?.removeObject(forKey: pendingKey)
        open(id)
    }

    static func open(_ id: String) {
        Task { await PlayerModel.shared.play(videoID: id) }
    }
}
