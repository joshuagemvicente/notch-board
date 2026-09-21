import XCTest
import UniformTypeIdentifiers
@testable import NotchBoard

final class CardDragPayloadTests: XCTestCase {
    func testStringFromNSString() {
        XCTAssertEqual(CardDragPayload.string(from: "linear/abc-123" as NSString), "linear/abc-123")
    }

    func testStringFromUTF8Data() {
        let id = "trello/64abc"
        XCTAssertEqual(CardDragPayload.string(from: id.data(using: .utf8)), id)
    }

    func testItemProviderAdvertisesUTF8PlainText() {
        let provider = CardDragPayload.itemProvider(cardID: "  linear/issue-1  ")
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
        XCTAssertTrue(provider.canLoadObject(ofClass: NSString.self))
    }

    func testLoadCardIDViaObject() async {
        let provider = CardDragPayload.itemProvider(cardID: "github/PVTI_kw")
        let expectation = expectation(description: "card id loaded")
        var loaded: String?

        let started = CardDragPayload.loadCardID(from: [provider]) { id in
            loaded = id
            expectation.fulfill()
        }
        XCTAssertTrue(started)
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(loaded, "github/PVTI_kw")
    }
}
