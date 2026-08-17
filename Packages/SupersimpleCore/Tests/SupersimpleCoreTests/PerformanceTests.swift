import Foundation
import Testing

@testable import SupersimpleCore

@Suite("Performance benchmarks", .enabled(if: ProcessInfo.processInfo.environment["RUN_PERF_TESTS"] != nil))
struct PerformanceTests {

    @Test("Search returns quickly across many notes")
    func searchThroughput() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = try NoteSearchIndex(databaseURL: dir.appendingPathComponent("p.db"))
        for i in 0..<10_000 {
            let note = Note(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                tags: [Tag(name: i.isMultiple(of: 2) ? "even" : "odd")],
                body: "Note \(i) covers the quick brown fox and swift programming concepts end to end."
            )
            try index.upsert(note: note)
        }

        let started = DispatchTime.now()
        let results = index.search("brown fox")
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        #expect(!results.isEmpty)
        #expect(ms < 500, "Expected search under 500ms, got \(ms) ms for 10k notes")
    }

    @Test("Markdown scanning a large body stays linear")
    func scannerThroughput() {
        let body = String(repeating: "inline $x^2$ math and ```swift\nlet a = 1\n``` and tag #demo.\n", count: 2_000)
        let started = DispatchTime.now()
        _ = MarkdownScanner.mathSegments(in: body)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        #expect(ms < 1000, "Expected scan under 1000ms, got \(ms) ms")
    }
}
