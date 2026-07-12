import Foundation

nonisolated struct HerdrPreflightService: Sendable {
    typealias Execute = @Sendable (String) async throws -> SSHExecResult

    let commandBuilder: HerdrRemoteCommandBuilder
    let evaluator: HerdrPreflightEvaluator

    init(
        commandBuilder: HerdrRemoteCommandBuilder,
        evaluator: HerdrPreflightEvaluator = HerdrPreflightEvaluator()
    ) {
        self.commandBuilder = commandBuilder
        self.evaluator = evaluator
    }

    func run(execute: Execute) async throws -> HerdrPreflightResult {
        let result = try await execute(commandBuilder.status())
        if result.exitStatus == 127 {
            return .binaryMissing
        }
        guard result.exitStatus == 0 else {
            return .invalidStatus
        }
        return evaluator.evaluate(stdout: result.stdout)
    }
}
