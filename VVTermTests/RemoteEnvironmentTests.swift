import Testing
@testable import VVTerm

struct RemoteEnvironmentTests {
    @Test
    func windowsPlatformDetectionRecognizesCmdVerOutput() {
        let output = "Microsoft Windows [Version 10.0.20348.2522]"
        #expect(RemotePlatform.detect(from: output) == .windows)
    }

    @Test
    func windowsPowerShellEnvironmentDisablesTmuxAndMoshRuntime() {
        let environment = RemoteEnvironment(
            platform: .windows,
            shellProfile: .powershell(executableName: "powershell"),
            activeShellName: "powershell",
            powerShellExecutable: "powershell"
        )

        #expect(environment.supportsTmuxRuntime == false)
        #expect(environment.supportsMoshRuntime == false)
        #expect(environment.supportsWorkingDirectoryRestore == true)
    }

    @Test
    func windowsDefaultShellParserPrefersPwshExecutable() {
        let output = #"""
        HKEY_LOCAL_MACHINE\SOFTWARE\OpenSSH
            DefaultShell    REG_SZ    C:\Program Files\PowerShell\7\pwsh.exe
        """#

        #expect(RemoteEnvironmentResolver.powerShellExecutableName(inWindowsShellOutput: output) == "pwsh")
    }

    @Test
    func windowsPowerShellExecutableCandidatesPreferActiveShell() {
        #expect(RemoteEnvironmentResolver.powerShellExecutableCandidates(preferredExecutableName: "pwsh.exe") == ["pwsh", "powershell"])
        #expect(RemoteEnvironmentResolver.powerShellExecutableCandidates(preferredExecutableName: "powershell.exe") == ["powershell", "pwsh"])
        #expect(RemoteEnvironmentResolver.powerShellExecutableCandidates(preferredExecutableName: nil) == ["powershell", "pwsh"])
    }

    @Test
    func posixEnvironmentSupportsTmuxAndMoshRuntime() {
        let environment = RemoteEnvironment(
            platform: .linux,
            shellProfile: .posix(shellName: "zsh"),
            activeShellName: "zsh",
            powerShellExecutable: nil
        )

        #expect(environment.supportsTmuxRuntime == true)
        #expect(environment.supportsMoshRuntime == true)
        #expect(environment.supportsWorkingDirectoryRestore == true)
    }

    @Test
    func nushellProfileStillCountsAsPOSIXRuntime() {
        let environment = RemoteEnvironment(
            platform: .linux,
            shellProfile: .posix(shellName: "nu"),
            activeShellName: "nu",
            powerShellExecutable: nil
        )

        #expect(environment.supportsTmuxRuntime == true)
        #expect(environment.supportsMoshRuntime == true)
        #expect(environment.supportsWorkingDirectoryRestore == true)
    }

    @Test
    func windowsUnknownShellDisablesWorkingDirectoryRestore() {
        let environment = RemoteEnvironment(
            platform: .windows,
            shellProfile: .unknown(),
            activeShellName: nil,
            powerShellExecutable: "powershell"
        )

        #expect(environment.supportsTmuxRuntime == false)
        #expect(environment.supportsMoshRuntime == false)
        #expect(environment.supportsWorkingDirectoryRestore == false)
    }
}
