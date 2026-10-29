import SwiftUI

struct VideoCard: View {
    let video: Video
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(video: video)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if let d = video.duration {
                        Text(Self.format(d))
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white).padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if video.progress > 0.01 || video.watched {
                        GeometryReader { g in
                            Rectangle().fill(.red).frame(width: g.size.width * (video.watched ? 1 : video.progress), height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(video.watched ? 0.6 : 1)
                .overlay(alignment: .topTrailing) { quickActions }
            Text(video.title).font(.headline).lineLimit(2)
            HStack(spacing: 4) {
                Text(video.channelTitle)
                Text("·")
                Text(video.published, format: .relative(presentation: .named))
                if video.watchLater { Image(systemName: "clock.fill").font(.caption2) }
            }
            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await PlayerModel.shared.play(videoID: video.id) } }
        .task(id: video.id) {
            if video.duration == nil, let d = await VideoInfo.details(videoID: video.id)?.duration {
                video.duration = d
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 18) {
            Button {
                video.watched.toggle()
                if !video.watched { video.position = 0 }
                try? context.save()
            } label: {
                Image(systemName: video.watched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .accessibilityLabel(video.watched ? "Mark as unwatched" : "Mark as watched")
            Button {
                withAnimation { video.hidden.toggle() }
                try? context.save()
            } label: {
                Image(systemName: video.hidden ? "eye" : "eye.slash")
            }
            .accessibilityLabel(video.hidden ? "Show in feed" : "Hide")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .glassEffect(.regular.tint(.black.opacity(0.25)))
        .padding(8)
    }

    static func format(_ s: Double) -> String {
        Duration.seconds(s).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// 16:9 thumbnail without crop: HD image, small one if HD doesn't exist.
struct Thumbnail: View {
    let video: Video
    @State private var useSmall = false

    var body: some View {
        AsyncImage(url: useSmall ? video.smallThumbnailURL : video.wideThumbnailURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: Color.secondary.opacity(0.15).onAppear { useSmall = true }
            default: Color.secondary.opacity(0.15)
            }
        }
        .clipped()
    }
}

struct VideoActions: ViewModifier {
    let video: Video
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(video.watchLater ? "Remove from Watch later" : "Watch later",
                   systemImage: video.watchLater ? "clock.badge.xmark" : "clock") {
                video.watchLater.toggle(); try? context.save()
            }
            Button(video.watched ? "Mark as unwatched" : "Mark as watched",
                   systemImage: video.watched ? "eye.slash" : "eye") {
                video.watched.toggle()
                if !video.watched { video.position = 0 }
                try? context.save()
            }
            Button(video.hidden ? "Show in feed" : "Hide", systemImage: video.hidden ? "eye" : "eye.slash") {
                video.hidden.toggle(); try? context.save()
            }
            ShareLink(item: video.shareURL)
        }
    }
}

extension View {
    func videoActions(_ video: Video) -> some View { modifier(VideoActions(video: video)) }
}
