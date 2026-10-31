import AVKit
import SwiftData
import SwiftUI

struct PlayerView: View {
    @Bindable var model = PlayerModel.shared
    @Query private var channels: [Channel]
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                    Group {
                        if let symbol = model.hintSymbol {
                            Image(systemName: symbol).font(.system(size: 34, weight: .semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: symbol.hasPrefix("goforward") ? .trailing : .leading)
                                .padding(.horizontal, 40)
                        } else if model.boosted {
                            Label("2×", systemImage: "forward.fill").font(.subheadline.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .glassEffect(.regular.tint(.black.opacity(0.3)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, 10)
                        }
                    }
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.15), value: model.hintSymbol)
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

                    controls.padding(.top, 18)
                    secondary(video).padding(.top, 18)
                    channelRow(video).padding(.top, 20)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var controls: some View {
        HStack {
            Menu {
                Picker("Playback speed", selection: Binding(get: { model.rate }, set: { model.setRate($0) })) {
                    ForEach(PlayerModel.rates.reversed(), id: \.self) { r in
                        Text(r == 1 ? String(localized: "Normal") : String(format: "%g×", r)).tag(r)
                    }
                }
            } label: {
                Text(String(format: "%g×", model.rate))
                    .font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 46)
            }
            Spacer()
            Button { model.seek(by: -10) } label: { Image(systemName: "gobackward.10").font(.title2) }
            Spacer()
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 40))
                    .contentTransition(.symbolEffect(.replace))
            }
            Spacer()
            Button { model.seek(by: 10) } label: { Image(systemName: "goforward.10").font(.title2) }
            Spacer()
            Button { model.playNext() } label: { Image(systemName: "forward.end.fill").font(.title3) }
                .frame(width: 46)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 24)
    }

    private func secondary(_ video: Video) -> some View {
        HStack {
            Button { video.watchLater.toggle(); try? context.save() } label: {
                Image(systemName: video.watchLater ? "clock.fill" : "clock")
            }
            .accessibilityLabel("Watch later")
            Spacer()
            RoutePicker().frame(width: 30, height: 30)
            Spacer()
            ShareLink(item: video.shareURL) { Image(systemName: "square.and.arrow.up") }
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 44)
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
        .padding(.bottom, 30)
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
                    .onChanged { dragValue = min(max(0, $0.location.x / w), 1) * duration }
                    .onEnded { _ in if let v = dragValue { model.seek(to: v) }; dragValue = nil })
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
