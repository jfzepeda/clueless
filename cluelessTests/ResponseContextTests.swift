import Foundation
import PDFKit
import AppKit
import Testing
@testable import clueless

struct ResponseContextTests {
    @Test func contextPreservesSourcesAndTranscriptBudget() throws {
        var context = ResponseContext()
        try context.setText("Project notes")
        try context.add([ContextFile(name: "brief.md", text: "Release Friday")])
        let snapshot = context.requestContext(transcript: String(repeating: "x", count: 25_000), earlier: "Previous answer")
        #expect(snapshot.contains(String(repeating: "x", count: 24_000)))
        #expect(!snapshot.contains(String(repeating: "x", count: 24_001)))
        #expect(snapshot.contains("Pasted text:\nProject notes"))
        #expect(snapshot.contains("File: brief.md\nRelease Friday"))
        #expect(snapshot.contains("Previous answer"))
        context.remove(context.files[0].id)
        #expect(!context.requestContext(transcript: "", earlier: "").contains("Release Friday"))
        #expect(snapshot.contains("Release Friday"))
        context = ResponseContext()
        #expect(context.isEmpty)
    }

    @Test func limitsRejectChangesWithoutLosingExistingContext() throws {
        var context = ResponseContext()
        try context.setText(String(repeating: "a", count: 47_999))
        try context.add([ContextFile(name: "one.txt", text: "b")])
        #expect(context.characterCount == 48_000)
        #expect(throws: (any Error).self) { try context.setText(String(repeating: "c", count: 48_000)) }
        #expect(throws: (any Error).self) { try context.add([ContextFile(name: "two.txt", text: "c")]) }
        #expect(context.text.first == "a")
        #expect(context.files.count == 1)
        var empty = ResponseContext()
        try empty.setText("  \n")
        #expect(empty.isEmpty)
    }

    @Test func importsUTF8AndRejectsInvalidFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = directory.appendingPathComponent("notes.md")
        try "Résumé: mañana".write(to: valid, atomically: true, encoding: .utf8)
        #expect(try ResponseContext.readFile(valid).text == "Résumé: mañana")
        for (name, data) in [("empty.txt", Data()), ("binary.txt", Data([0xff])), ("image.png", Data([1])), ("broken.pdf", Data([1])), ("large.txt", Data(repeating: 65, count: 10_000_001)), ("long.txt", Data(repeating: 65, count: 48_001))] {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            #expect(throws: (any Error).self) { try ResponseContext.readFile(url) }
        }
        #expect(throws: (any Error).self) { try ResponseContext.readFile(directory.appendingPathComponent("missing.txt")) }
    }

    @MainActor @Test func extractsSelectablePDFText() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = "Reference document content"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try view.dataWithPDF(inside: view.bounds).write(to: url)
        #expect(try ResponseContext.readFile(url).text.contains("Reference document content"))
    }
}
