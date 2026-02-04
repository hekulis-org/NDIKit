import Testing
@testable import NDIKit

@Test func versionReturnsValidString() async throws {
    #expect(NDI.initialize())

    let version = NDI.version
    #expect(!version.isEmpty)
    #expect(version != "unknown")

    // NDI versions typically look like "6.0.1" or similar
    #expect(version.contains("."))

    NDI.destroy()
}
