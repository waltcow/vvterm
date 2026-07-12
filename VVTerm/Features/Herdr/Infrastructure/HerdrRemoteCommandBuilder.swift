import Foundation

nonisolated struct HerdrRemoteCommandBuilder: Sendable {
    let executable: String
    let sessionName: String

    init(executable: String = "herdr", sessionName: String) {
        self.executable = executable
        self.sessionName = sessionName
    }

    func status() -> String {
        command(arguments: ["status", "--json"])
    }

    func workspaceBridge() -> String {
        command(arguments: ["remote-client-bridge"])
    }

    func stopServer() -> String {
        command(arguments: ["server", "stop"])
    }

    func terminalObserve(target: String, cols: UInt16, rows: UInt16) -> String {
        command(arguments: [
            "terminal", "session", "observe", target,
            "--cols", String(cols), "--rows", String(rows),
        ])
    }

    func terminalControl(
        target: String,
        takeover: Bool,
        cols: UInt16,
        rows: UInt16
    ) -> String {
        var arguments = ["terminal", "session", "control", target]
        if takeover {
            arguments.append("--takeover")
        }
        arguments.append(contentsOf: ["--cols", String(cols), "--rows", String(rows)])
        return command(arguments: arguments)
    }

    private func command(arguments: [String]) -> String {
        let words = [executable, "--session", sessionName] + arguments
        return "exec " + words.map(Self.shellQuote).joined(separator: " ")
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}
