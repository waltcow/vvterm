import Testing
@testable import VVTerm

struct HerdrAppLifecyclePolicyTests {
    @Test
    func suspendsOnceInBackgroundAndResumesOnlyWhenFullyActive() {
        var policy = HerdrAppLifecyclePolicy(initialActivity: .foreground)

        let background = policy.update(.background, hasStartedSession: true)
        let duplicateBackground = policy.update(.background, hasStartedSession: true)
        let inactive = policy.update(.inactive, hasStartedSession: true)
        let foreground = policy.update(.foreground, hasStartedSession: true)

        #expect(background == .suspendBackground)
        #expect(duplicateBackground == .none)
        #expect(inactive == .none)
        #expect(foreground == .resumeForeground)
        #expect(!policy.isSuspendedForBackground)
    }

    @Test
    func initialBackgroundBlocksUntilForegroundWithoutDuplicateResume() {
        var policy = HerdrAppLifecyclePolicy(initialActivity: .background)

        #expect(policy.isSuspendedForBackground)
        let inactive = policy.update(.inactive, hasStartedSession: true)
        let foreground = policy.update(.foreground, hasStartedSession: true)
        let duplicateForeground = policy.update(.foreground, hasStartedSession: true)

        #expect(inactive == .none)
        #expect(foreground == .resumeForeground)
        #expect(duplicateForeground == .none)
    }

    @Test
    func routeWithoutMountedSessionDoesNotRequestConnectionWork() {
        var policy = HerdrAppLifecyclePolicy(initialActivity: .foreground)

        let background = policy.update(.background, hasStartedSession: false)
        let foreground = policy.update(.foreground, hasStartedSession: false)

        #expect(background == .none)
        #expect(foreground == .none)
    }
}
