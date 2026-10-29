import Foundation

enum WatchRules {
    static func isWatched(position: Double, duration: Double?) -> Bool {
        guard let duration, duration > 0 else { return false }
        return position >= duration * 0.9 || duration - position <= 30
    }
}
