#if os(iOS)
import Combine
import Foundation
import GameController
import UIKit
import os.log

@MainActor
final class TerminalKeyboardCoordinator: ObservableObject {
    struct StateInputs: Equatable {
        var viewActive: Bool
        var activePaneConnected: Bool
        var activePaneWindowAttached: Bool
        var userHidKeyboard: Bool
        var hardwareKeyboardAttached: Bool
        var findNavigatorActive: Bool
    }

    @Published private(set) var isUserHidden = false
    @Published private(set) var isHardwareKeyboardAttached = false

    var terminalProvider: ((UUID) -> GhosttyTerminalView?)?

    private var activePaneId: UUID?
    private var viewActive = false
    private var paneConnectedById: [UUID: Bool] = [:]
    private var paneWindowAttachedById: [UUID: Bool] = [:]
    private var findNavigatorActive = false
    private var syncScheduled = false
    private var isSyncing = false
    private var pendingSyncAfterCurrent = false
    private var pendingReason = "initial"
    private var lastManagedPaneId: UUID?
    /// Ground truth from UIKit: whether the software keyboard is on screen.
    /// Consulted only during explicit user actions to repair a session whose
    /// keyboard presentation silently failed — never drives sync on its own.
    private var isSoftwareKeyboardOnScreen = false
    private var wantsPresentationRefresh = false
    private var pendingPresentationVerify = false
    /// Rebuilding a session UIKit refuses to present cannot succeed by
    /// repetition; cap attempts until the keyboard actually shows (which
    /// resets the count) so repeated taps don't flicker the accessory bar.
    private var presentationRefreshAttemptCount = 0
    private let presentationRefreshAttemptLimit = 2
    private var keyboardVisibilityObservers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        // keyboardWillShow marks the keyboard as on-screen at animation START:
        // otherwise the presentation verify races the animation and bounces a
        // keyboard that is already on its way (visible as show-hide-show
        // flicker on connect).
        keyboardVisibilityObservers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSoftwareKeyboardOnScreen = true
                    self?.presentationRefreshAttemptCount = 0
                }
            }
        )
        keyboardVisibilityObservers.append(
            center.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSoftwareKeyboardOnScreen = true
                    self?.presentationRefreshAttemptCount = 0
                }
            }
        )
        keyboardVisibilityObservers.append(
            center.addObserver(
                forName: UIResponder.keyboardDidHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSoftwareKeyboardOnScreen = false
                }
            }
        )
        // A session that survives a scene transition (iPhone Mirroring
        // connect, unlock) can be stale for the remote-input pipeline: keys
        // arrive nowhere until the session is rebuilt. Request a one-shot
        // refresh evaluation on activation; it only bounces when the session
        // is active with no keyboard on screen.
        keyboardVisibilityObservers.append(
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.wantsPresentationRefresh = true
                    self.presentationRefreshAttemptCount = 0
                    self.markDirty(reason: "sceneActivated")
                }
            }
        )
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm",
        category: "KeyboardCoordinator"
    )

    /// Whether the terminal should hold the text-input session (first
    /// responder). A hardware keyboard does NOT end the session — key events
    /// need an active responder; UIKit suppresses the software keyboard on
    /// its own while hardware is attached, and the accessory bar is gated
    /// separately.
    nonisolated static func desiredKeyboardVisible(inputs: StateInputs) -> Bool {
        inputs.viewActive
            && inputs.activePaneConnected
            && inputs.activePaneWindowAttached
            && !inputs.userHidKeyboard
            && !inputs.findNavigatorActive
    }

    func setActivePane(_ paneId: UUID?) {
        guard activePaneId != paneId else { return }
        activePaneId = paneId
        markDirty(reason: "activePane")
    }

    func setViewActive(_ active: Bool) {
        guard viewActive != active else { return }
        viewActive = active
        markDirty(reason: "viewActive")
    }

    func setPaneConnected(_ connected: Bool, for paneId: UUID) {
        guard paneConnectedById[paneId] != connected else { return }
        paneConnectedById[paneId] = connected
        markDirty(reason: "paneConnected")
    }

    func removePane(_ paneId: UUID) {
        let didRemoveConnected = paneConnectedById.removeValue(forKey: paneId) != nil
        let didRemoveWindow = paneWindowAttachedById.removeValue(forKey: paneId) != nil
        if activePaneId == paneId {
            activePaneId = nil
            markDirty(reason: "removeActivePane")
        } else if didRemoveConnected || didRemoveWindow {
            markDirty(reason: "removePane")
        }
    }

    func setWindowAttached(_ attached: Bool, for paneId: UUID) {
        guard paneWindowAttachedById[paneId] != attached else { return }
        paneWindowAttachedById[paneId] = attached
        markDirty(reason: "windowAttached")
    }

    func setHardwareKeyboard(_ attached: Bool) {
        guard isHardwareKeyboardAttached != attached else { return }
        isHardwareKeyboardAttached = attached
        markDirty(reason: "hardwareKeyboard")
    }

    func setFindNavigatorActive(_ active: Bool) {
        guard findNavigatorActive != active else { return }
        findNavigatorActive = active
        markDirty(reason: "findNavigator")
    }

    func userRequestedHide() {
        guard !isUserHidden else { return }
        isUserHidden = true
        markDirty(reason: "userHide")
    }

    func userRequestedShow() {
        wantsPresentationRefresh = true
        if isUserHidden {
            isUserHidden = false
        }
        markDirty(reason: "userShow")
    }

    func directTouchOnTerminal() {
        guard !isUserHidden else { return }
        wantsPresentationRefresh = true
        markDirty(reason: "directTouch")
    }

    private var currentInputs: StateInputs {
        let paneId = activePaneId
        return StateInputs(
            viewActive: viewActive,
            activePaneConnected: paneId.flatMap { paneConnectedById[$0] } ?? false,
            activePaneWindowAttached: paneId.flatMap { paneWindowAttachedById[$0] } ?? false,
            userHidKeyboard: isUserHidden,
            hardwareKeyboardAttached: isHardwareKeyboardAttached,
            findNavigatorActive: findNavigatorActive
        )
    }

    private func markDirty(reason: String) {
        pendingReason = reason
        if isSyncing {
            pendingSyncAfterCurrent = true
            return
        }
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.sync()
        }
    }

    private func sync() {
        syncScheduled = false
        guard !isSyncing else {
            pendingSyncAfterCurrent = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if pendingSyncAfterCurrent {
                pendingSyncAfterCurrent = false
                markDirty(reason: "coalescedResync")
            }
        }

        let inputs = currentInputs
        let desired = Self.desiredKeyboardVisible(inputs: inputs)
        let accessoryEnabled = !inputs.hardwareKeyboardAttached
            && !inputs.findNavigatorActive
            && !inputs.userHidKeyboard

        let reason = pendingReason

        if let previousPaneId = lastManagedPaneId,
           previousPaneId != activePaneId,
           let previousTerminal = terminalProvider?(previousPaneId) {
            previousTerminal.setTerminalInputAccessoryEnabled(false)
            let before = previousTerminal.keyboardCoordinatorDiagnosticSnapshot()
            if before.isFirstResponder {
                previousTerminal.releaseTerminalInput()
                logCommand(
                    desired: false,
                    reason: reason,
                    inputs: inputs,
                    before: before,
                    after: previousTerminal.keyboardCoordinatorDiagnosticSnapshot()
                )
            }
            lastManagedPaneId = nil
        }

        guard let activePaneId,
              let terminal = terminalProvider?(activePaneId) else {
            logger.info("command=none reason=\(self.pendingReason, privacy: .public) desired=\(desired) noActiveTerminal=true viewActive=\(inputs.viewActive) connected=\(inputs.activePaneConnected) windowAttached=\(inputs.activePaneWindowAttached) userHidden=\(inputs.userHidKeyboard) hardware=\(inputs.hardwareKeyboardAttached) find=\(inputs.findNavigatorActive)")
            return
        }
        lastManagedPaneId = activePaneId

        terminal.setTerminalInputAccessoryEnabled(accessoryEnabled)

        let refreshRequested = wantsPresentationRefresh
        wantsPresentationRefresh = false

        let before = terminal.keyboardCoordinatorDiagnosticSnapshot()
        // Compare against the software input session, not the combined
        // responder state: the view can hold first responder for native
        // selection, which must not read as "keyboard is up".
        guard before.isSoftwareInputActive != desired else {
            if desired,
               refreshRequested,
               before.isSoftwareInputActive,
               !isSoftwareKeyboardOnScreen,
               !inputs.hardwareKeyboardAttached,
               // A present hardware keyboard (e.g. iPhone Mirroring before the
               // first keystroke latches it) means iOS is suppressing the
               // software keyboard deliberately — a rebuild cannot help and
               // only flickers the accessory bar. Presence is used solely to
               // skip repairs, never for policy.
               GCKeyboard.coalesced == nil,
               presentationRefreshAttemptCount < presentationRefreshAttemptLimit {
                // The session is active but the keyboard never presented
                // (silent UIKit presentation failure). The user explicitly
                // asked for the keyboard: rebuild the session once.
                presentationRefreshAttemptCount += 1
                terminal.releaseTerminalInput()
                _ = terminal.acquireTerminalInput()
                let after = terminal.keyboardCoordinatorDiagnosticSnapshot()
                logger.info("command=refresh reason=\(self.pendingReason, privacy: .public) viewActive=\(inputs.viewActive) connected=\(inputs.activePaneConnected) windowAttached=\(inputs.activePaneWindowAttached) userHidden=\(inputs.userHidKeyboard) hardware=\(inputs.hardwareKeyboardAttached) find=\(inputs.findNavigatorActive) keyboardOnScreen=\(self.isSoftwareKeyboardOnScreen) afterFirstResponder=\(after.isFirstResponder) afterSoftwareInput=\(after.isSoftwareInputActive)")
                return
            }
            logger.info("command=steady reason=\(self.pendingReason, privacy: .public) desired=\(desired) viewActive=\(inputs.viewActive) connected=\(inputs.activePaneConnected) windowAttached=\(inputs.activePaneWindowAttached) userHidden=\(inputs.userHidKeyboard) hardware=\(inputs.hardwareKeyboardAttached) find=\(inputs.findNavigatorActive) window=\(before.windowAttached) keyWindow=\(before.windowIsKey) scene=\(before.sceneActivationState, privacy: .public) firstResponder=\(before.isFirstResponder) softwareInput=\(before.isSoftwareInputActive) keyboardOnScreen=\(self.isSoftwareKeyboardOnScreen)")
            return
        }

        if desired {
            terminal.acquireTerminalInput()
        } else {
            terminal.releaseTerminalInput()
        }

        let after = terminal.keyboardCoordinatorDiagnosticSnapshot()
        logCommand(
            desired: desired,
            reason: reason,
            inputs: inputs,
            before: before,
            after: after
        )

        if desired, after.isSoftwareInputActive {
            schedulePresentationVerify()
        } else if !desired {
            presentationRefreshAttemptCount = 0
        }
    }

    /// UIKit can accept the input session yet silently fail to present the
    /// keyboard. Verify each acquire once: if the keyboard has not arrived
    /// shortly after, rebuild the session a single time. One-shot per
    /// acquire — cannot loop.
    private func schedulePresentationVerify() {
        guard !pendingPresentationVerify else { return }
        pendingPresentationVerify = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.pendingPresentationVerify = false
            guard !self.isSoftwareKeyboardOnScreen else { return }
            guard let paneId = self.activePaneId,
                  let terminal = self.terminalProvider?(paneId) else { return }
            let inputs = self.currentInputs
            guard Self.desiredKeyboardVisible(inputs: inputs),
                  !inputs.hardwareKeyboardAttached,
                  // See the refresh path: with a hardware keyboard present,
                  // no software keyboard is a deliberate iOS decision.
                  GCKeyboard.coalesced == nil else { return }
            let snapshot = terminal.keyboardCoordinatorDiagnosticSnapshot()
            guard snapshot.isSoftwareInputActive else { return }
            guard self.presentationRefreshAttemptCount < self.presentationRefreshAttemptLimit else { return }
            self.presentationRefreshAttemptCount += 1
            terminal.releaseTerminalInput()
            _ = terminal.acquireTerminalInput()
            let after = terminal.keyboardCoordinatorDiagnosticSnapshot()
            self.logger.info("command=verifyRefresh keyboardOnScreen=\(self.isSoftwareKeyboardOnScreen) afterFirstResponder=\(after.isFirstResponder) afterSoftwareInput=\(after.isSoftwareInputActive)")
        }
    }

    private func logCommand(
        desired: Bool,
        reason: String,
        inputs: StateInputs,
        before: TerminalKeyboardCoordinatorDiagnosticSnapshot,
        after: TerminalKeyboardCoordinatorDiagnosticSnapshot
    ) {
        logger.info(
            "command=\(desired ? "acquire" : "release", privacy: .public) desired=\(desired) reason=\(reason, privacy: .public) viewActive=\(inputs.viewActive) connected=\(inputs.activePaneConnected) windowAttached=\(inputs.activePaneWindowAttached) userHidden=\(inputs.userHidKeyboard) hardware=\(inputs.hardwareKeyboardAttached) find=\(inputs.findNavigatorActive) beforeWindow=\(before.windowAttached) beforeKeyWindow=\(before.windowIsKey) beforeScene=\(before.sceneActivationState, privacy: .public) beforeFirstResponder=\(before.isFirstResponder) beforeSoftwareInput=\(before.isSoftwareInputActive) afterWindow=\(after.windowAttached) afterKeyWindow=\(after.windowIsKey) afterScene=\(after.sceneActivationState, privacy: .public) afterFirstResponder=\(after.isFirstResponder) afterSoftwareInput=\(after.isSoftwareInputActive)"
        )
    }
}
#endif
