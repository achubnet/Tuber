import AVKit
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Bindable var model = PlayerModel.shared
    @Query private var channels: [Channel]
    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            // Landscape: video only, edge to edge.
            videoArea(fullscreen: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        } else {
            portrait
        }
    }

    private func videoArea(fullscreen: Bool) -> some View {
                ZStack(alignment: .topLeading) {
                    VideoSurface(model: model)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black)
                    if model.isLoading { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    if let error = model.error {
                        VStack(spacing: 8) {
                            Text(error).foregroundStyle(.white)
                            Button("Retry") { model.retry() }.buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    PassthroughHost(isActive: { [model] in model.controlsVisible && !model.isLoading && model.error == nil }) {
                        VideoOverlay(model: model, fullscreen: fullscreen)
                    }
                    if model.boosted {
                        Label("2×", systemImage: "forward.fill").font(.subheadline.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassEffect(.regular.tint(.black.opacity(0.3)))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                    if let badge = model.skippedBadge {
                        Label(badge, systemImage: "forward.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassEffect(.regular.tint(.black.opacity(0.3)))
                            .foregroundStyle(.white)
                            .padding(10)
                            .transition(.opacity)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .animation(.easeInOut, value: model.skippedBadge)
    }

    private var portrait: some View {
        VStack(spacing: 0) {
            // Video stays pinned while the details scroll under it.
            videoArea(fullscreen: false)
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SegmentBar(model: model).padding(.horizontal).padding(.top, 14)

                if let video = model.current {
                    Text(video.title).font(.title3.bold()).padding(.horizontal).padding(.top, 12)
                    HStack(spacing: 6) {
                        if let views = model.viewCount {
                            Label {
                                Text(views, format: .number.notation(.compactName))
                            } icon: {
                                Image(systemName: "eye")
                            }
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel(Text("\(views) views"))
                            Text("·")
                        }
                        Text(video.published, format: .relative(presentation: .named))
                    }
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal).padding(.top, 2)

                    actions(video).padding(.top, 16)
                    channelRow(video).padding(.top, 20)
                    if let text = model.details?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        DescriptionBox(text: text) { model.seek(to: $0); if !model.isPlaying { model.togglePlay() } }
                            .padding(.horizontal).padding(.bottom, 30)
                    }
                }
            }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Glass action buttons under the video, evenly spread across the width.
    private func actions(_ video: Video) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Menu {
                Picker("Playback speed", selection: Binding(get: { model.rate }, set: { model.setRate($0) })) {
                    ForEach(PlayerModel.rates.reversed(), id: \.self) { r in
                        Text(r == 1 ? String(localized: "Normal") : String(format: "%g×", r)).tag(r)
                    }
                }
            } label: {
                ActionLabel(icon: "gauge.with.dots.needle.67percent", title: Text(verbatim: String(format: "%g×", model.rate)))
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
            Button { model.playNext() } label: { ActionLabel(icon: "forward.end.fill", title: Text("Next")) }
            Button { video.watchLater.toggle(); try? context.save() } label: {
                ActionLabel(icon: video.watchLater ? "clock.fill" : "clock", title: Text("Later"))
            }
            if model.audioOptions.count > 1 {
                Menu {
                    Picker("Audio track", selection: Binding(get: { model.audioOption },
                                                             set: { if let o = $0 { model.selectAudio(o) } })) {
                        ForEach(model.audioOptions, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                    }
                } label: {
                    ActionLabel(icon: "waveform", title: Text(model.audioOption.flatMap { o in
                        o.locale.flatMap { $0.localizedString(forLanguageCode: $0.language.languageCode?.identifier ?? "") }
                    }?.capitalized ?? String(localized: "Audio track")))
                }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
            }
            ShareLink(item: video.shareURL) { ActionLabel(icon: "square.and.arrow.up", title: Text("Share")) }
            ActionLabel(icon: "airplay.video", title: Text("AirPlay"))
                .overlay(alignment: .top) { RoutePicker().frame(width: 48, height: 48).opacity(0.02) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func channelRow(_ video: Video) -> some View {
        let subscribed = channels.contains { $0.id == video.channelID }
        return HStack {
            Text(video.channelTitle).font(.headline)
            Spacer()
            Button(subscribed ? "Subscribed" : "Subscribe") {
                if let c = channels.first(where: { $0.id == video.channelID }) {
                    context.delete(c)
                } else if !video.channelID.isEmpty {
                    context.insert(Channel(id: video.channelID, title: video.channelTitle))
                }
                try? context.save()
            }
            .buttonStyle(.bordered)
            .tint(subscribed ? .secondary : .red)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

/// Video description with tappable timecodes (seek) and links.
private struct DescriptionBox: View {
    let text: String
    let seek: (Double) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.linked(text))
                .font(.subheadline)
                .tint(.red)
                .lineLimit(expanded ? nil : 4)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "tuber-seek", let s = Double(url.host() ?? "") { seek(s); return .handled }
                    // Other YouTube videos open in the app.
                    if let id = VideoLink.videoID(from: url) { Deeplink.open(id); return .handled }
                    return .systemAction
                })
            if text.count > 180 || text.split(separator: "\n").count > 4 {
                Button(expanded ? "Less" : "More") { withAnimation { expanded.toggle() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
    }

    /// Marks 1:23 / 1:02:03 as seek links and web addresses as links.
    static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let ns = text as NSString
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let url = m.url, let r = Range(m.range, in: text), let ar = Range(r, in: result) else { continue }
                result[ar].link = url
            }
        }
        for m in text.matches(of: /\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b/) {
            let h: Double = m.1.flatMap { Double($0) } ?? 0
            let mm: Double = Double(m.2) ?? 0
            let ss: Double = Double(m.3) ?? 0
            let total = Int(h * 3600 + mm * 60 + ss)
            guard ss < 60, let ar = Range(m.range, in: result), let url = URL(string: "tuber-seek://\(total)") else { continue }
            result[ar].link = url
        }
        return result
    }
}

/// Red icon in a glass circle with a caption under it.
private struct ActionLabel: View {
    let icon: String
    let title: Text

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.red)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
            title.font(.caption).foregroundStyle(Color(.secondaryLabel)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// Progress with SponsorBlock segments marked in green; drag to seek.
struct SegmentBar: View {
    @Bindable var model: PlayerModel
    @State private var dragValue: Double?

    var body: some View {
        let duration = max(model.duration, 1)
        let value = dragValue ?? model.time
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    ForEach(model.segments, id: \.self) { s in
                        Rectangle().fill(.green.opacity(0.85))
                            .frame(width: max(2, (s.end - s.start) / duration * w))
                            .offset(x: s.start / duration * w)
                    }
                    Capsule().fill(.primary).frame(width: min(w, value / duration * w))
                }
                .frame(height: dragValue == nil ? 4 : 8)
                .clipShape(Capsule())
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(max(0, $0.location.x / w), 1) * duration; model.holdControls() }
                    .onEnded { _ in if let v = dragValue { model.seek(to: v) }; dragValue = nil; model.scheduleHideControls() })
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.15), value: dragValue == nil)
            HStack {
                Text(format(value))
                Spacer()
                Text("-" + format(max(0, duration - value)))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func format(_ s: Double) -> String { Duration.seconds(s).formatted(.time(pattern: s >= 3600 ? .hourMinuteSecond : .minuteSecond)) }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .secondaryLabel
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
