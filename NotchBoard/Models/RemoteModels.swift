import Foundation

// MARK: - Date parsing (Trello emits ISO8601 with fractional seconds)

enum APIDate {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFractional.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - Trello REST DTOs

struct TrelloMemberDTO: Decodable {
    let id: String
    /// Absent when the request asks for `fields=id` only.
    let username: String?
    let fullName: String?
}

struct TrelloBoardDTO: Decodable {
    let id: String
    let name: String
    let url: String
    let closed: Bool
    let pinned: Bool?
    let starred: Bool?
    let dateLastActivity: String?
    let idOrganization: String?
}

struct TrelloCardDTO: Decodable {
    let id: String
    let idBoard: String
    let idList: String?
    let name: String
    let url: String
    let due: String?
    let dueComplete: Bool?
    let dateLastActivity: String?
    let closed: Bool
    let idMembers: [String]
}

struct TrelloListDTO: Decodable {
    let id: String
    let name: String
    let pos: Double?
    let closed: Bool?
    let cards: [TrelloListCardDTO]?
}

struct TrelloListCardDTO: Decodable {
    let id: String
    let name: String
    let url: String?
    let due: String?
    let dueComplete: Bool?
    let dateLastActivity: String?
    let closed: Bool?
    let idMembers: [String]?
    let idList: String?
}

struct TrelloCardDetailDTO: Decodable {
    let id: String
    let name: String
    let desc: String?
    let url: String?
    let due: String?
    let dueComplete: Bool?
    let dateLastActivity: String?
    let closed: Bool?
    let idList: String?
    let idMembers: [String]?
    let list: TrelloListNameDTO?
}

struct TrelloListNameDTO: Decodable {
    let id: String?
    let name: String?
}

// MARK: - GitHub GraphQL DTOs

struct GraphQLResponse<Data: Decodable>: Decodable {
    let data: Data?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

struct PageInfoDTO: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

// Query 1 — viewer + projects
struct ViewerProjectsDTO: Decodable {
    let viewer: Viewer
    struct Viewer: Decodable {
        let login: String
        let projectsV2: ProjectConnection
    }
    struct ProjectConnection: Decodable {
        let nodes: [Project]
        let pageInfo: PageInfoDTO
    }
    struct Project: Decodable {
        let id: String
        let title: String
        let number: Int
        let url: String
        let updatedAt: String?
        let closed: Bool
        let owner: Owner?
    }
    struct Owner: Decodable {
        let login: String?
    }
}

// Query 2 — items for one project
struct ProjectItemsDTO: Decodable {
    let node: Project?
    struct Project: Decodable {
        let url: String
        let updatedAt: String?
        let items: ItemConnection
    }
    struct ItemConnection: Decodable {
        let nodes: [Item]
        let pageInfo: PageInfoDTO
    }
    struct Item: Decodable {
        let id: String
        let type: String
        let updatedAt: String?
        let isArchived: Bool
        let content: Content?
        let fieldValues: FieldValueConnection
    }
    struct Content: Decodable {
        let title: String?
        let url: String?
        let closed: Bool?
        let updatedAt: String?
        let assignees: AssigneeConnection?
    }
    struct AssigneeConnection: Decodable {
        let nodes: [Assignee]
    }
    struct Assignee: Decodable {
        let login: String
    }
    struct FieldValueConnection: Decodable {
        let nodes: [FieldValue]
    }
    // Covers both members of the ProjectV2ItemFieldValue union:
    // single-select -> { name, field { name } }, date -> { date }
    struct FieldValue: Decodable {
        let name: String?
        let field: Field?
        let date: String?
    }
    struct Field: Decodable {
        let name: String?
    }
}

// Query 3 — repo -> linked projects
struct RepoProjectsDTO: Decodable {
    let repository: Repository?
    struct Repository: Decodable {
        let projectsV2: ViewerProjectsDTO.ProjectConnection
    }
}

// Query for validating a token (viewer.login only)
struct ViewerLoginDTO: Decodable {
    let viewer: Viewer
    struct Viewer: Decodable {
        let login: String
    }
}