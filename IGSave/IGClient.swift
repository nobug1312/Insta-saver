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
    case loginRequired, accessBlocked, invalidResponse, notFound, rateLimit, failed(Int)

    var errorDescription: String? {
        switch self {
        case .loginRequired: "This post belongs to a private account. Log in with an account that can view it."
        case .accessBlocked: "Instagram blocked access to this content. This does not mean it is private. Try again later."
        case .invalidResponse: "Instagram returned an unexpected response. Please try again later."
        case .notFound: "Couldn't find anything at this link."
        case .rateLimit: "Instagram is limiting requests. Try again in a few minutes."
        case .failed(let c): "Something went wrong (error \(c))."
        }
    }
}

enum IGClient {
    private static let base = "https://www.instagram.com"
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func resolve(_ link: IGLink, session: URLSession = .shared) async throws -> Resolved {
        let result: Resolved
        switch link {
        case .post(let code):
            do {
                return try await publicPost(code, session: session)
            } catch IGError.loginRequired {
                if Session.get() == nil { throw IGError.loginRequired }
            } catch IGError.rateLimit {
                throw IGError.rateLimit
            } catch {
                if Session.get() == nil { throw error }
            }
            let data = try await api("/api/v1/media/\(shortcodeToId(code))/info/", session: session)
            let nodes = data["items"] as? [[String: Any]] ?? []
            let isReel = nodes.first?["product_type"] as? String == "clips"
            result = Resolved(user: user(nodes.first?["user"]), kind: isReel ? "Reel" : "Post",
                              items: nodes.flatMap(toItems))
        case .highlight(let id):
            let r = try await reel("highlight:\(id)", session: session)
            result = Resolved(user: user(r["user"]), kind: "Highlight",
                              items: (r["items"] as? [[String: Any]] ?? []).flatMap(toItems))
        case .story(let name, let storyId):
            let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let prof = try await api("/api/v1/users/web_profile_info/?username=\(enc)", session: session)
            let u = (prof["data"] as? [String: Any])?["user"] as? [String: Any]
            guard let uid = u?["id"] as? String else { throw IGError.notFound }
            let all = try await reel(uid, session: session)["items"] as? [[String: Any]] ?? []
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

    private static func publicPost(_ code: String, session: URLSession) async throws -> Resolved {
        var url = URL(string: base)!
        for part in ["p", code, "embed", "captioned"] { url.appendPathComponent(part) }
        url.appendPathComponent("")
        let req = URLRequest(url: url)
        let (data, _) = try await fetch(req, session: session, authenticated: false)
        guard let html = String(data: data, encoding: .utf8) else { throw IGError.invalidResponse }
        // The embed stores media in a JSON-encoded string; decode it without executing page scripts.
        let pattern = #""contextJSON"\s*:\s*("(?:\\.|[^"\\])*")"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: html),
                  let context = try? JSONSerialization.jsonObject(
                    with: Data(html[valueRange].utf8), options: .fragmentsAllowed) as? String,
                  let json = try? JSONSerialization.jsonObject(with: Data(context.utf8)) as? [String: Any],
                  let gql = json["gql_data"] as? [String: Any],
                  let node = gql["shortcode_media"] as? [String: Any],
                  node["shortcode"] as? String == code else { continue }
            return try resolvedPublicPost(node)
        }
        throw IGError.accessBlocked
    }

    private static func resolvedPublicPost(_ node: [String: Any]) throws -> Resolved {
        let owner = node["owner"] as? [String: Any]
        if owner?["is_private"] as? Bool == true { throw IGError.loginRequired }
        let items = publicItems(node)
        guard !items.isEmpty else { throw IGError.notFound }
        return Resolved(user: user(owner), kind: node["is_video"] as? Bool == true ? "Reel" : "Post", items: items)
    }

    private static func publicItems(_ node: [String: Any]) -> [MediaItem] {
        if let sidecar = node["edge_sidecar_to_children"] as? [String: Any],
           let edges = sidecar["edges"] as? [[String: Any]] {
            return edges.flatMap { edge in
                (edge["node"] as? [String: Any]).map(publicItems) ?? []
            }
        }
        let thumb = (node["display_url"] as? String).flatMap(URL.init(string:))
        if node["is_video"] as? Bool == true {
            guard let video = (node["video_url"] as? String).flatMap(URL.init(string:)) else { return [] }
            return [MediaItem(isVideo: true, url: video, thumb: thumb)]
        }
        return thumb.map { [MediaItem(isVideo: false, url: $0, thumb: $0)] } ?? []
    }

    private static func api(_ path: String, session: URLSession) async throws -> [String: Any] {
        try await request(URLRequest(url: URL(string: base + path)!), session: session, authenticated: true)
    }

    private static func request(_ request: URLRequest, session: URLSession, authenticated: Bool) async throws -> [String: Any] {
        let (data, resp) = try await fetch(request, session: session, authenticated: authenticated)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let type = resp?.value(forHTTPHeaderField: "Content-Type") ?? ""
            if type.contains("text/html") { throw IGError.accessBlocked }
            throw IGError.invalidResponse
        }
        if json["status"] as? String == "fail" { throw IGError.accessBlocked }
        return json
    }

    private static func fetch(_ request: URLRequest, session: URLSession, authenticated: Bool) async throws -> (Data, HTTPURLResponse?) {
        var req = request
        req.timeoutInterval = 30
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpShouldHandleCookies = false
        if authenticated {
            if let all = Session.get() { req.setValue(all, forHTTPHeaderField: "Cookie") }
            if let csrf = cookie("csrftoken") { req.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }
        }

        let (data, resp) = try await session.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 401, 403: throw IGError.accessBlocked
        case 404: throw IGError.notFound
        case 429: throw IGError.rateLimit
        case 200..<300: break
        case let c: throw IGError.failed(c)
        }
        return (data, resp as? HTTPURLResponse)
    }

    private static func reel(_ reelId: String, session: URLSession) async throws -> [String: Any] {
        let enc = reelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reelId
        let data = try await api("/api/v1/feed/reels_media/?reel_ids=\(enc)", session: session)
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
