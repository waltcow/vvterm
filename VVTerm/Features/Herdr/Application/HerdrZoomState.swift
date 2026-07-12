import Foundation

struct HerdrZoomState {
    private(set) var presentationOverrides = TerminalPresentationOverrides.empty

    mutating func apply(_ action: TerminalZoomAction) -> TerminalZoomResult {
        presentationOverrides = presentationOverrides.applyingZoom(action)
        return TerminalZoomResult(
            presentationOverrides: presentationOverrides,
            effectiveFontSize: presentationOverrides.resolvedFontSize()
        )
    }
}
