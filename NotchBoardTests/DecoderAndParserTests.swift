import Testing
import Foundation
@testable import NotchBoard

struct GitRemoteParserTests {
    @Test func parsesSSHForm() throws {
        let result = try #require(GitRemoteParser.parse("git@github.com:acme/widget.git"))
        #expect(result.owner == "acme")
        #expect(result.name == "widget")
    }

    @Test func parsesHTTPSForm() throws {
        let result = try #require(GitRemoteParser.parse("https://github.com/acme/widget.git"))
        #expect(result.owner == "acme")
        #expect(result.name == "widget")
    }

    @Test func parsesHTTPSWithoutGitSuffix() throws {
        let result = try #require(GitRemoteParser.parse("https://github.com/acme/widget"))
        #expect(result.owner == "acme")
        #expect(result.name == "widget")
    }

    @Test func rejectsNonGitHubHost() {
        #expect(GitRemoteParser.parse("git@gitlab.com:acme/widget.git") == nil)
        #expect(GitRemoteParser.parse("https://bitbucket.org/acme/widget.git") == nil)
    }

    @Test func rejectsLocalPaths() {
        #expect(GitRemoteParser.parse("/Users/gem/projects/foo") == nil)
        #expect(GitRemoteParser.parse("~/projects/foo") == nil)
    }

    @Test func rejectsMalformedURLs() {
        #expect(GitRemoteParser.parse("git@github.com") == nil)
        #expect(GitRemoteParser.parse("https://github.com/acme") == nil)
        #expect(GitRemoteParser.parse("") == nil)
    }

    @Test func trimsWhitespace() throws {
        let result = try #require(GitRemoteParser.parse("  git@github.com:acme/widget.git\n"))
        #expect(result.owner == "acme")
    }
}

struct DecoderTests {
    @Test func decodesTrelloMemberIdOnly() throws {
        let json = """
        {"id":"m1"}
        """
        let dto = try JSONDecoder().decode(TrelloMemberDTO.self, from: Data(json.utf8))
        #expect(dto.id == "m1")
        #expect(dto.username == nil)
    }

    @Test func decodesTrelloMemberWithUsername() throws {
        let json = """
        {"id":"m1","username":"gem","fullName":"Gem"}
        """
        let dto = try JSONDecoder().decode(TrelloMemberDTO.self, from: Data(json.utf8))
        #expect(dto.username == "gem")
        #expect(dto.fullName == "Gem")
    }

    @Test func decodesTrelloBoard() throws {
        let json = """
        {"id":"b1","name":"Launch","url":"https://trello.com/b/abc","closed":false,"pinned":true,"dateLastActivity":"2024-01-15T10:30:00.000Z","idOrganization":"org1"}
        """
        let dto = try JSONDecoder().decode(TrelloBoardDTO.self, from: Data(json.utf8))
        #expect(dto.name == "Launch")
        #expect(dto.pinned == true)
        #expect(dto.dateLastActivity != nil)
        #expect(APIDate.parse(dto.dateLastActivity) != nil)
    }

    @Test func decodesTrelloCardWithMembers() throws {
        let json = """
        {"id":"c1","idBoard":"b1","idList":"l1","name":"Fix bug","url":"https://trello.com/c/xyz","due":"2024-02-01T00:00:00.000Z","dueComplete":false,"dateLastActivity":"2024-01-20T00:00:00.000Z","closed":false,"idMembers":["m1","m2"]}
        """
        let dto = try JSONDecoder().decode(TrelloCardDTO.self, from: Data(json.utf8))
        #expect(dto.idBoard == "b1")
        #expect(dto.idMembers == ["m1", "m2"])
        #expect(dto.dueComplete == false)
    }

    @Test func decodesGitHubViewerProjects() throws {
        let json = """
        {"data":{"viewer":{"login":"gem","projectsV2":{"nodes":[{"id":"PVT_1","title":"Roadmap","number":3,"url":"https://github.com/orgs/acme/projects/3","updatedAt":"2024-01-15T10:30:00Z","closed":false,"owner":{"login":"acme"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
        """
        let response = try JSONDecoder().decode(GraphQLResponse<ViewerProjectsDTO>.self, from: Data(json.utf8))
        let project = try #require(response.data?.viewer.projectsV2.nodes.first)
        #expect(project.title == "Roadmap")
        #expect(project.owner?.login == "acme")
        #expect(response.data?.viewer.login == "gem")
    }

    @Test func decodesGitHubProjectItems() throws {
        let json = """
        {"data":{"node":{"url":"https://github.com/orgs/acme/projects/3","updatedAt":"2024-01-15T10:30:00Z","items":{"nodes":[{"id":"PVTI_1","type":"ISSUE","updatedAt":"2024-01-14T09:00:00Z","isArchived":false,"content":{"title":"Ship v2","url":"https://github.com/acme/widget/issues/42","closed":false,"updatedAt":"2024-01-14T09:00:00Z","assignees":{"nodes":[{"login":"gem"}]}},"fieldValues":{"nodes":[{"name":"In Progress","field":{"name":"Status"}}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
        """
        let response = try JSONDecoder().decode(GraphQLResponse<ProjectItemsDTO>.self, from: Data(json.utf8))
        let item = try #require(response.data?.node?.items.nodes.first)
        #expect(item.type == "ISSUE")
        #expect(item.content?.assignees?.nodes.first?.login == "gem")
        #expect(item.fieldValues.nodes.first?.name == "In Progress")
    }

    @Test func surfacesGraphQLErrors() throws {
        let json = """
        {"data":null,"errors":[{"message":"Not Found"}]}
        """
        let response = try JSONDecoder().decode(GraphQLResponse<ViewerLoginDTO>.self, from: Data(json.utf8))
        #expect(response.errors?.first?.message == "Not Found")
        #expect(response.data == nil)
    }
}