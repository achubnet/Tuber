import AVFoundation
import MediaPlayer
import SwiftData
import SwiftUI

@Observable @MainActor
final class PlayerModel {
    static let shared = PlayerModel()

    let player = AVPlayer()
    var current: Video?
    var isPresented = false
    var segments: [Segment] = []
    var viewCount: Int?
    var skippedBadge: String?
    var error: String?
    var isLoading = false
    var isPlaying = false
    var time: Double = 0
    var duration: Double = 0
    var rate: Float = 1
    var inBackground = false
    var pipActive = false
    var controlsVisible = true
    var seekBurst: SeekBurst?
    var audioOptions: [AVMediaSelectionOption] = []
    var audioOption: AVMediaSelectionOption?
    var boosted = false
    static let rates: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    private var context: ModelContext { Persistence.container.mainContext }
    private var lastSave = Date.distantPast
    private var badgeTask: Task<Void, Never>?
    private var loadID = UUID()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        setupRemoteCommands()
    }

    // MARK: Loading

    func play(videoID: String, present: Bool = true) async {
        guard VideoLink.isValidID(videoID) else { return }
        saveProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        time = 0
        duration = 0
        isPlaying = false
        let token = UUID(); loadID = token
        error = nil
        isLoading = true
        segments = []
        viewCount = nil
        audioOptions = []
        audioOption = nil
        controlsVisible = true
        if present { isPresented = true }

        var video = try? context.fetch(FetchDescriptor<Video>(predicate: #Predicate { $0.id == videoID })).first
        if video == nil || video?.title.isEmpty == true {
            let d = await VideoInfo.details(videoID: videoID)
            video = Video.upsert(id: videoID, channelID: d?.channelID ?? "", channelTitle: d?.channelTitle ?? "",
                                 title: d?.title ?? "", duration: d?.duration, in: context)
        }
        guard let video, loadID == token else { return }
        current = video
        video.lastPlayedAt = .now
        try? context.save()

        async let segs = SponsorBlock.segments(videoID: videoID, categories: Settings.skipCategories)
        Task {
            let views = await VideoInfo.details(videoID: videoID)?.viewCount
            if loadID == token { viewCount = views }
        }
        do {
            let url = try await StreamResolver.playableURL(videoID: videoID)
            guard loadID == token else { return }
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            Task { await configureMedia(item, token: token) }
            let start = video.watched ? 0 : video.position
            if start > 5 { await player.seek(to: CMTime(seconds: start - 2, preferredTimescale: 600)) }
            try? AVAudioSession.sharedInstance().setActive(true)
            player.defaultRate = rate
            player.play()
            isPlaying = true
            isLoading = false
            updateNowPlaying()
            scheduleHideControls()
        } catch {
            guard loadID == token else { return }
            isLoading = false
            self.error = String(localized: "Could not load the video")
        }
        let loaded = await segs
        if loadID == token { segments = loaded }
    }

    /// Subtitles off; audio track in the app language when the video has one.
    private func configureMedia(_ item: AVPlayerItem, token: UUID) async {
        if let subs = try? await item.asset.loadMediaSelectionGroup(for: .legible) { item.select(nil, in: subs) }
        guard let audio = try? await item.asset.loadMediaSelectionGroup(for: .audible), loadID == token,
              audio.options.count > 1 else { return }
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if let match = audio.options.first(where: { $0.locale?.language.languageCode?.identifier == lang }) {
            item.select(match, in: audio)
        }
        audioOptions = audio.options
        audioOption = item.currentMediaSelection.selectedMediaOption(in: audio)
    }

    func selectAudio(_ option: AVMediaSelectionOption) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        item.select(option, in: group)
        audioOption = option
    }

    func retry() {
        guard let id = current?.id else { return }
        Task { await play(videoID: id) }
    }

    // MARK: Controls

    func togglePlay() {
        if isPlaying { player.pause(); saveProgress() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
        scheduleHideControls()
    }

    private var controlsTask: Task<Void, Never>?
    func toggleControls() {
        controlsVisible.toggle()
        scheduleHideControls()
    }

    /// Controls fade out after a few seconds while playing.
    func scheduleHideControls() {
        controlsTask?.cancel()
        guard controlsVisible, isPlaying else { return }
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, isPlaying { controlsVisible = false }
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        time = seconds
        updateNowPlaying()
    }

    func seek(by delta: Double) { seek(to: time + delta) }

    func setRate(_ value: Float) {
        rate = value
        player.defaultRate = value
        if isPlaying { player.rate = value }
        updateNowPlaying()
    }

    /// Temporary 2x while the video is held, without changing the chosen speed.
    func setBoost(_ on: Bool) {
        boosted = on
        guard isPlaying else { return }
        player.rate = on ? 2 : rate
    }

    struct SeekBurst: Equatable {
        var forward: Bool
        var seconds: Int
    }

    /// YouTube-style double tap: 10 s per tap, taps in a row add up.
    private var burstTask: Task<Void, Never>?
    func burstSeek(forward: Bool) {
        if seekBurst?.forward == forward { seekBurst?.seconds += 10 } else { seekBurst = SeekBurst(forward: forward, seconds: 10) }
        controlsVisible = false
        seek(by: forward ? 10 : -10)
        burstTask?.cancel()
        burstTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            if !Task.isCancelled { seekBurst = nil }
        }
    }

    func playNext() {
        guard let current else { return }
        let subscribed = Set((try? context.fetch(FetchDescriptor<Channel>()))?.map(\.id) ?? [])
        let feed = (try? context.fetch(FetchDescriptor<Video>(sortBy: [SortDescriptor(\.published, order: .reverse)]))) ?? []
        let queue = feed.filter { subscribed.contains($0.channelID) && !$0.watched && $0.id != current.id }
        let next = queue.first { $0.published < current.published } ?? queue.first
        if let next { Task { await play(videoID: next.id, present: false) } }
    }

    // MARK: Ticking

    private func tick(_ t: Double) {
        guard t.isFinite, !isLoading, let current else { return }
        time = t
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
            if current.duration == nil { current.duration = d }
        }
        if let target = SkipLogic.skipTarget(at: t, segments: segments) {
            let category = segments.first { $0.start <= t && t < $0.end }?.category ?? "sponsor"
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
            time = target
            showBadge(Self.categoryName(category))
        }
        if Date.now.timeIntervalSince(lastSave) > 5 { saveProgress() }
        if player.timeControlStatus == .paused, isPlaying, t >= duration - 1, duration > 0 {
            isPlaying = false
            saveProgress()
        }
    }

    func saveProgress() {
        guard let current, time > 0 else { return }
        current.position = time
        if WatchRules.isWatched(position: time, duration: duration > 0 ? duration : current.duration) {
            current.watched = true
            current.watchLater = false
        }
        lastSave = .now
        try? context.save()
        updateNowPlaying()
    }

    private func showBadge(_ text: String) {
        skippedBadge = text
        badgeTask?.cancel()
        badgeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { skippedBadge = nil }
        }
    }

    static func categoryName(_ category: String) -> String {
        switch category {
        case "sponsor": String(localized: "Sponsor")
        case "selfpromo": String(localized: "Self-promo")
        case "interaction": String(localized: "Reminder")
        case "intro": String(localized: "Intro")
        case "outro": String(localized: "Outro")
        case "preview": String(localized: "Preview")
        case "music_offtopic": String(localized: "Non-music")
        case "filler": String(localized: "Filler")
        default: category
        }
    }

    // MARK: Now Playing

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { @Sendable _ in Self.remote { if !$0.isPlaying { $0.togglePlay() } } }
        c.pauseCommand.addTarget { @Sendable _ in Self.remote { if $0.isPlaying { $0.togglePlay() } } }
        c.togglePlayPauseCommand.addTarget { @Sendable _ in Self.remote { $0.togglePlay() } }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { @Sendable _ in Self.remote { $0.seek(by: 10) } }
        c.skipBackwardCommand.addTarget { @Sendable _ in Self.remote { $0.seek(by: -10) } }
        c.nextTrackCommand.addTarget { @Sendable _ in Self.remote { $0.playNext() } }
        c.changePlaybackPositionCommand.addTarget { @Sendable e in
            let pos = (e as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            return Self.remote { $0.seek(to: pos) }
        }
    }

    nonisolated private static func remote(_ action: @escaping @MainActor (PlayerModel) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in action(PlayerModel.shared) }
        return .success
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.channelTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(for: current)
    }

    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private var artworkID: String?
    private func loadArtwork(for video: Video) {
        guard artworkID != video.id, let url = video.thumbnailURL else { return }
        artworkID = video.id
        Task {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = UIImage(data: data) else { return }
            let art = Self.artwork(image)
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = art
        }
    }
}
