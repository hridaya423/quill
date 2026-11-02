import Foundation
import Testing
@testable import Quill

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["QUILL_REGISTRY"] != nil))
func registryInstallsAVerifiedArchiveOnce() async throws {
    let argv = try await Registry.argv("opencode", local: nil)
    #expect(argv.last == "acp")
    #expect(FileManager.default.isExecutableFile(atPath: argv[0]))
    let start = Date()
    #expect(try await Registry.argv("opencode", local: nil) == argv)
    #expect(Date().timeIntervalSince(start) < 1)
}
