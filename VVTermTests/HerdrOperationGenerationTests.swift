import Testing
@testable import VVTerm

struct HerdrOperationGenerationTests {
    @Test
    func cancelledOperationCannotFinishNewReplacement() {
        var generation = HerdrOperationGeneration()
        let old = generation.begin()
        generation.invalidate()
        let current = generation.begin()

        let staleFinish = generation.finish(old)
        #expect(!staleFinish)
        #expect(generation.currentID == current)

        let currentFinish = generation.finish(current)
        #expect(currentFinish)
        #expect(generation.currentID == nil)
    }
}
