import AVKit
import SwiftUI

/// AVPlayerViewController for fullscreen, PiP and AirPlay. Detaches in background so audio keeps playing.
struct VideoSurface: UIViewControllerRepresentable {
    @Bindable var model: PlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = model.player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.updatesNowPlayingInfoCenter = false
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.delegate = context.coordinator
        context.coordinator.attachGestures(to: vc.view)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        let detach = model.inBackground && !model.pipActive
        if detach, vc.player != nil { vc.player = nil }
        if !detach, vc.player == nil { vc.player = model.player }
    }

    @MainActor final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate, @MainActor UIGestureRecognizerDelegate {
        let model: PlayerModel
        init(model: PlayerModel) { self.model = model }

        /// YouTube-style gestures: double tap left/right half seeks 5 s, press and hold plays at 2x.
        func attachGestures(to view: UIView) {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.4
            for g in [doubleTap, hold] as [UIGestureRecognizer] {
                g.cancelsTouchesInView = false
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let forward = g.location(in: view).x > view.bounds.midX
            model.seek(by: forward ? 5 : -5)
            model.flashHint(forward ? "goforward.5" : "gobackward.5")
        }

        @objc private func held(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: model.setBoost(true)
            case .ended, .cancelled, .failed: model.setBoost(false)
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func playerViewControllerWillStartPictureInPicture(_ vc: AVPlayerViewController) {
            model.pipActive = true
        }

        func playerViewControllerDidStopPictureInPicture(_ vc: AVPlayerViewController) {
            model.pipActive = false
        }

        func playerViewController(_ vc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
            model.isPresented = true
            completion(true)
        }
    }
}
