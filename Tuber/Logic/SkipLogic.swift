import Foundation

struct Segment: Decodable, Sendable, Hashable {
    let segment: [Double]
    let category: String
    var start: Double { segment.first ?? 0 }
    var end: Double { segment.last ?? 0 }
}

enum SkipLogic {
    /// If `t` is inside a segment, returns the end of the furthest chain of overlapping/adjacent segments.
    static func skipTarget(at t: Double, segments: [Segment]) -> Double? {
        let sorted = segments.sorted { $0.start < $1.start }
        guard var end = sorted.first(where: { $0.start <= t && t < $0.end - 0.3 })?.end else { return nil }
        for s in sorted where s.start <= end + 0.5 && s.end > end { end = s.end }
        return end
    }
}
