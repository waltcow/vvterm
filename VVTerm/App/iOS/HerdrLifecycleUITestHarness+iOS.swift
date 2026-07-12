#if os(iOS) && DEBUG
import SwiftUI

struct HerdrLifecycleUITestHarness: View {
    @State private var selectedView = ConnectionViewTab.terminal.id
    @State private var mountState = HerdrTabMountState()
    @State private var lifecyclePolicy = HerdrAppLifecyclePolicy(
        initialActivity: .foreground
    )
    @State private var lastLifecycleAction = HerdrAppLifecycleAction.none

    var body: some View {
        VStack(spacing: 16) {
            Text("ready=true")
                .accessibilityIdentifier("vvterm.herdrLifecycle.ready")

            Text(diagnostics)
                .accessibilityIdentifier("vvterm.herdrLifecycle.diagnostics")

            HStack {
                Button("Terminal") {
                    selectedView = ConnectionViewTab.terminal.id
                }
                .accessibilityIdentifier("vvterm.herdrLifecycle.tab.terminal")

                Button("Herdr") {
                    selectedView = ConnectionViewTab.herdr.id
                    mountState.observe(isSelected: true)
                }
                .accessibilityIdentifier("vvterm.herdrLifecycle.tab.herdr")
            }

            HStack {
                Button("Background") { updateActivity(.background) }
                    .accessibilityIdentifier("vvterm.herdrLifecycle.background")
                Button("Inactive") { updateActivity(.inactive) }
                    .accessibilityIdentifier("vvterm.herdrLifecycle.inactive")
                Button("Foreground") { updateActivity(.foreground) }
                    .accessibilityIdentifier("vvterm.herdrLifecycle.foreground")
            }

            ZStack {
                Color.gray.opacity(0.15)
                    .overlay(Text("Terminal placeholder"))

                if mountState.hasMounted {
                    let isVisible = selectedView == ConnectionViewTab.herdr.id
                    HerdrLifecycleIdentityProbe()
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                        .accessibilityHidden(!isVisible)
                }
            }
        }
        .padding()
    }

    private var diagnostics: String {
        "mounted=\(mountState.hasMounted) selected=\(selectedView) "
            + "suspended=\(lifecyclePolicy.isSuspendedForBackground) "
            + "action=\(String(describing: lastLifecycleAction))"
    }

    private func updateActivity(_ activity: HerdrAppActivity) {
        lastLifecycleAction = lifecyclePolicy.update(
            activity,
            hasStartedSession: mountState.hasMounted
        )
    }
}

private struct HerdrLifecycleIdentityProbe: View {
    @State private var identity = UUID().uuidString
    @State private var inputCount = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("identity=\(identity) input=\(inputCount)")
                .accessibilityIdentifier("vvterm.herdrLifecycle.identity")
            Button("Input") {
                inputCount += 1
            }
            .accessibilityIdentifier("vvterm.herdrLifecycle.input")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .foregroundStyle(.white)
    }
}
#endif
