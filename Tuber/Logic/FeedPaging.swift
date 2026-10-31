import Foundation

/// Stops endless loading when older pages keep adding nothing visible (e.g. all already watched).
enum FeedPaging {
    static let maxEmptyLoads = 3

    static func emptyStreak(visibleBefore: Int, visibleAfter: Int, streak: Int) -> Int {
        visibleAfter > visibleBefore ? 0 : streak + 1
    }

    static func canAutoLoad(hasMore: Bool, emptyStreak: Int) -> Bool {
        hasMore && emptyStreak < maxEmptyLoads
    }
}
