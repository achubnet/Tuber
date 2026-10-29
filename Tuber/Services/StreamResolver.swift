import Foundation
import YouTubeKit

enum StreamResolver {
    /// Prefers an HLS manifest (best quality, one URL), falls back to the best muxed stream.
    static func playableURL(videoID: String) async throws -> URL {
        let video = YouTube(videoID: videoID, methods: [.local, .remote])
        if let hls = try? await video.livestreams.first?.url {
            return hls
        }
        let muxed = try await video.streams
            .filter { $0.includesVideoAndAudioTrack && $0.isNativelyPlayable }
            .highestResolutionStream()
        guard let url = muxed?.url else { throw URLError(.resourceUnavailable) }
        return url
    }
}
