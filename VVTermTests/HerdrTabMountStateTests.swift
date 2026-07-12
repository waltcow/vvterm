import Testing
@testable import VVTerm

struct HerdrTabMountStateTests {
    @Test
    func mountsLazilyAndStaysMountedAfterSelectionChanges() {
        var state = HerdrTabMountState()

        state.observe(isSelected: false)
        #expect(!state.hasMounted)

        state.observe(isSelected: true)
        #expect(state.hasMounted)

        state.observe(isSelected: false)
        #expect(state.hasMounted)
    }
}
