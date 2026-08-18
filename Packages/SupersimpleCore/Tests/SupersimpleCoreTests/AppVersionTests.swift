import Foundation
import Testing

@testable import SupersimpleCore

@Suite("AppVersion")
struct AppVersionTests {

    @Test("Parses tags with or without a v prefix")
    func parseTag() {
        #expect(AppVersion(parsing: "v0.1.0") == AppVersion(parts: [0, 1, 0]))
        #expect(AppVersion(parsing: "0.1.0.12") == AppVersion(parts: [0, 1, 0, 12]))
    }

    @Test("Treats a newer release tag as greater than the running marketing version")
    func compare() {
        #expect(AppVersion(parsing: "0.1.0") < AppVersion(parsing: "v0.1.0.1"))
        #expect(AppVersion(parsing: "0.1.0.1") < AppVersion(parsing: "0.1.1"))
        #expect(AppVersion(parsing: "0.1.0") == AppVersion(parsing: "0.1.0.0"))
        #expect(!(AppVersion(parsing: "0.1.0") < AppVersion(parsing: "0.1.0.0")))
    }
}
