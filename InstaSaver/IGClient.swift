import Foundation

struct MediaItem: Identifiable {
    let id = UUID()
    let isVideo: Bool
    let url: URL
    let thumb: URL?
}

struct IGUser {
    let username: String
}

struct Resolved {
    let user: IGUser?
    let kind: String
    let items: [MediaItem]
}

enum IGError: LocalizedError {
    case loginRequired, notFound, rateLimit, failed(Int)

    var errorDescription: String? {
        switch self {
        case .loginRequired: "This content is private. Log in to download it."
        case .notFound: "Couldn't find anything at this link."
        case .rateLimit: "Instagram is limiting requests. Try again in a few minutes."
        case .failed(let c): "Something went wrong (error \(c))."
        }
    }
}

enum IGClient {
    private static let base = "https://www.instagram.com"
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func resolve(_ link: IGLink) async throws -> Resolved {
        let result: Resolved
        switch link {
        case .post(let code):
            let data = try await api("/api/v1/media/\(shortcodeToId(code))/info/")
            let nodes = data["items"] as? [[String: Any]] ?? []
            let isReel = nodes.first?["product_type"] as? String == "clips"
            result = Resolved(user: user(nodes.first?["user"]), kind: isReel ? "Reel" : "Post",
                              items: nodes.flatMap(toItems))
        case .highlight(let id):
            let r = try await reel("highlight:\(id)")
            result = Resolved(user: user(r["user"]), kind: "Highlight",
                              items: (r["items"] as? [[String: Any]] ?? []).flatMap(toItems))
        case .story(let name, let storyId):
            let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let prof = try await api("/api/v1/users/web_profile_info/?username=\(enc)")
            let u = (prof["data"] as? [String: Any])?["user"] as? [String: Any]
            guard let uid = u?["id"] as? String else { throw IGError.notFound }
            let all = try await reel(uid)["items"] as? [[String: Any]] ?? []
            let picked = storyId.map { sid in all.filter { "\($0["pk"] ?? "")" == sid } } ?? all
            result = Resolved(user: user(u), kind: "Story", items: (picked.isEmpty ? all : picked).flatMap(toItems))
        }
        if result.items.isEmpty { throw IGError.notFound }
        return result
    }

    private static func user(_ any: Any?) -> IGUser? {
        (any as? [String: Any])?["username"].flatMap { $0 as? String }.map(IGUser.init)
    }

    private static func cookie(_ name: String) -> String? {
        Session.get()?.components(separatedBy: "; ")
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    private static func shortcodeToId(_ code: String) -> String {
        var id: UInt64 = 0
        for c in code { id = id &* 64 &+ UInt64(alphabet.firstIndex(of: c) ?? 0) }
        return String(id)
    }

    private static func api(_ path: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: base + path)!)
        req.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpShouldHandleCookies = false
        if let all = Session.get() { req.setValue(all, forHTTPHeaderField: "Cookie") }
        if let csrf = cookie("csrftoken") { req.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 401, 403: throw IGError.loginRequired
        case 404: throw IGError.notFound
        case 429: throw IGError.rateLimit
        case 200..<300: break
        case let c: throw IGError.failed(c)
        }
        // HTML login page instead of JSON means the session is missing or expired
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw IGError.loginRequired }
        return json
    }

    private static func reel(_ reelId: String) async throws -> [String: Any] {
        let enc = reelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reelId
        let data = try await api("/api/v1/feed/reels_media/?reel_ids=\(enc)")
        let r = (data["reels"] as? [String: Any])?[reelId] as? [String: Any]
            ?? (data["reels_media"] as? [[String: Any]])?.first
        guard let r else { throw IGError.notFound }
        return r
    }

    private static func toItems(_ node: [String: Any]) -> [MediaItem] {
        if let carousel = node["carousel_media"] as? [[String: Any]] { return carousel.flatMap(toItems) }
        let thumbStr = ((node["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]])?.first?["url"] as? String
        let thumb = thumbStr.flatMap(URL.init(string:))
        if let v = (node["video_versions"] as? [[String: Any]])?.first?["url"] as? String, let u = URL(string: v) {
            return [MediaItem(isVideo: true, url: u, thumb: thumb)]
        }
        if let thumb { return [MediaItem(isVideo: false, url: thumb, thumb: thumb)] }
        return []
    }
}
