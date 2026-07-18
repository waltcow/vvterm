import Foundation

struct HerdrVolumeScrollPolicy {
    static let captureVolume: Float = 0.5

    private static let comparisonTolerance: Float = 0.0005
    private(set) var isActive = false

    mutating func activate() {
        isActive = true
    }

    mutating func deactivate() {
        isActive = false
    }

    func scrollDirection(for volume: Float) -> HerdrScrollDirection? {
        guard isActive, volume.isFinite else { return nil }
        let delta = volume - Self.captureVolume
        guard abs(delta) > Self.comparisonTolerance else { return nil }
        return delta > 0 ? .up : .down
    }
}
