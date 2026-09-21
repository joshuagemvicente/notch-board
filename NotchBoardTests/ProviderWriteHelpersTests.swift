import XCTest
@testable import NotchBoard

final class ProviderWriteHelpersTests: XCTestCase {
    func testGitHubOptionIDMapsByName() {
        let options = [
            GitHubStatusMapping.StatusOption(id: "opt-todo", name: "Todo"),
            GitHubStatusMapping.StatusOption(id: "opt-doing", name: "In Progress"),
        ]
        XCTAssertEqual(GitHubStatusMapping.optionID(forStatusName: "In Progress", options: options), "opt-doing")
        XCTAssertEqual(GitHubStatusMapping.optionID(forStatusName: nil, options: options), GitHubStatusMapping.uncategorizedID)
        XCTAssertEqual(GitHubStatusMapping.optionID(forStatusName: "Missing", options: options), GitHubStatusMapping.uncategorizedID)
    }

    func testGitHubColumnsIncludeUncategorizedWhenNeeded() {
        let options = [GitHubStatusMapping.StatusOption(id: "opt-todo", name: "Todo")]
        let withGap = GitHubStatusMapping.columns(options: options, cardStatusNames: ["Todo", nil])
        XCTAssertEqual(withGap.map(\.nativeID), ["opt-todo", GitHubStatusMapping.uncategorizedID])

        let clean = GitHubStatusMapping.columns(options: options, cardStatusNames: ["Todo", "Todo"])
        XCTAssertEqual(clean.map(\.nativeID), ["opt-todo"])
    }

    func testJiraTransitionPickerMatchesStatusName() {
        let transitions = [
            JiraTransitionPicker.Transition(id: "11", toStatusName: "In Progress"),
            JiraTransitionPicker.Transition(id: "21", toStatusName: "Done"),
        ]
        XCTAssertEqual(
            JiraTransitionPicker.transitionID(matching: "in progress", in: transitions),
            "11"
        )
        XCTAssertNil(JiraTransitionPicker.transitionID(matching: "Blocked", in: transitions))
    }

    func testJiraADFPlainText() {
        let adf: [String: Any] = [
            "type": "doc",
            "content": [
                [
                    "type": "paragraph",
                    "content": [
                        ["type": "text", "text": "Hello"],
                        ["type": "text", "text": "world"],
                    ],
                ],
            ],
        ]
        XCTAssertEqual(JiraADFText.plainText(from: adf), "Hello\nworld")
        XCTAssertEqual(JiraADFText.plainText(from: " plain "), "plain")
        XCTAssertNil(JiraADFText.plainText(from: "   "))
    }
}
