import Foundation

struct VideoDetails: Sendable {
    let title: String
    let channelID: String
    let channelTitle: String
    let duration: Double?
    var viewCount: Int?
}

enum VideoInfo {
    static func details(videoID: String) async -> VideoDetails? {
        guard let json = try? await InnerTube.post("player", body: ["videoId": videoID]),
              let d = json["videoDetails"] as? [String: Any] else { return nil }
        return VideoDetails(title: d["title"] as? String ?? "",
                            channelID: d["channelId"] as? String ?? "",
                            channelTitle: d["author"] as? String ?? "",
                            duration: (d["lengthSeconds"] as? String).flatMap(Double.init),
                            viewCount: (d["viewCount"] as? String).flatMap(Int.init))
    }
}
