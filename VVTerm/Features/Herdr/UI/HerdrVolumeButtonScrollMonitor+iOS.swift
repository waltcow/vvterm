#if os(iOS)
import AVFAudio
import MediaPlayer
import UIKit

@MainActor
final class HerdrVolumeButtonScrollMonitor {
    var onScroll: ((HerdrScrollDirection) -> Void)?

    private let audioSession = AVAudioSession.sharedInstance()
    private let volumeView: MPVolumeView
    private var volumeObservation: NSKeyValueObservation?
    private var originalVolume: Float?
    private var policy = HerdrVolumeScrollPolicy()
    private var enabled = false

    init() {
        let volumeView = MPVolumeView(frame: CGRect(x: -2, y: -2, width: 1, height: 1))
        volumeView.showsVolumeSlider = true
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        volumeView.accessibilityElementsHidden = true
        self.volumeView = volumeView
    }

    func attach(to hostView: UIView) {
        guard volumeView.superview !== hostView else { return }
        volumeView.removeFromSuperview()
        hostView.addSubview(volumeView)
        volumeView.layoutIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            startCapturing()
        } else {
            stopCapturing()
        }
    }

    func detach() {
        enabled = false
        stopCapturing()
        volumeView.removeFromSuperview()
        onScroll = nil
    }

    private func startCapturing() {
        guard volumeObservation == nil, volumeSlider != nil else {
            enabled = false
            return
        }

        originalVolume = audioSession.outputVolume
        policy.activate()
        volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) {
            [weak self] _, change in
            guard let volume = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.handleObservedVolume(volume)
            }
        }
        setSystemVolume(HerdrVolumeScrollPolicy.captureVolume)
    }

    private func stopCapturing() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        policy.deactivate()
        if let originalVolume {
            setSystemVolume(originalVolume)
        }
        originalVolume = nil
    }

    private func handleObservedVolume(_ volume: Float) {
        guard enabled, let direction = policy.scrollDirection(for: volume) else { return }
        onScroll?(direction)
        setSystemVolume(HerdrVolumeScrollPolicy.captureVolume)
    }

    private func setSystemVolume(_ volume: Float) {
        guard let volumeSlider else { return }
        volumeSlider.setValue(volume, animated: false)
        volumeSlider.sendActions(for: .valueChanged)
    }

    private var volumeSlider: UISlider? {
        findVolumeSlider(in: volumeView)
    }

    private func findVolumeSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider {
            return slider
        }
        for subview in view.subviews {
            if let slider = findVolumeSlider(in: subview) {
                return slider
            }
        }
        return nil
    }
}
#endif
