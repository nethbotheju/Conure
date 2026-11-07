import Foundation
import XCTest
@testable import ConureApp

final class MarkdownNotesTests: XCTestCase {
    func testParsesHeadingsParagraphsListsQuotesAndRules() {
        let source = """
        # Release 0.3.0

        Fixes the **library** layout.
        Second line continues.

        ## Changes
        - Faster library scan
        - Speaker rename persists
        1. First
        2. Second

        > Note
        ---
        """
        XCTAssertEqual(MarkdownNotesParser.parse(source), [
            .heading(level: 1, text: "Release 0.3.0"),
            .paragraph("Fixes the **library** layout. Second line continues."),
            .heading(level: 2, text: "Changes"),
            .bullet("Faster library scan"),
            .bullet("Speaker rename persists"),
            .numbered(number: "1", text: "First"),
            .numbered(number: "2", text: "Second"),
            .quote("Note"),
            .rule,
        ])
    }

    func testFencedCodePreservesIndentationAndBlankLines() {
        let source = """
        ```swift
        let value = 1

            print(value)
        ```
        """
        XCTAssertEqual(MarkdownNotesParser.parse(source), [
            .code("let value = 1\n\n    print(value)"),
        ])
    }

    func testUnclosedFenceBecomesCode() {
        XCTAssertEqual(MarkdownNotesParser.parse("```\nstill code"), [
            .code("still code"),
        ])
    }

    func testNumberedListsRequireSpaceAndDelimiter() {
        XCTAssertEqual(MarkdownNotesParser.parse("1.Item"), [.paragraph("1.Item")])
        XCTAssertEqual(MarkdownNotesParser.parse("2026. Not a list"), [.paragraph("2026. Not a list")])
        XCTAssertEqual(MarkdownNotesParser.parse("1) Item"), [.numbered(number: "1", text: "Item")])
    }

    func testHashtagWithoutSpaceIsAParagraph() {
        XCTAssertEqual(MarkdownNotesParser.parse("#hashtag"), [.paragraph("#hashtag")])
    }

    func testInlineMarkdownIsParsed() throws {
        let attributed = MarkdownNotesParser.attributed("Fixes the **library** and [links](https://example.com).")
        XCTAssertEqual(String(attributed.characters), "Fixes the library and links.")
    }
}
