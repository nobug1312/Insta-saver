import Foundation

enum IGLink {
    case post(shortcode: String)
    case story(username: String, storyId: String?)
    case highlight(id: String)

    init?(_ input: String) {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, host == "instagram.com" || host.hasSuffix(".instagram.com")
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), i + 1 < parts.count {
            self = .post(shortcode: parts[i + 1])
        } else if parts.count >= 3, parts[0] == "stories", parts[1] == "highlights" {
            self = .highlight(id: parts[2])
        } else if parts.count >= 2, parts[0] == "stories" {
            self = .story(username: parts[1], storyId: parts.count > 2 ? parts[2] : nil)
        } else {
            return nil
        }
    }
}
