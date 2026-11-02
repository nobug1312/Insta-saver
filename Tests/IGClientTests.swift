import Foundation

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct TestFailure: Error {
    let message: String
}

@main
struct IGClientTests {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(message: message) }
    }

    static func embed(_ node: [String: Any]) throws -> Data {
        let context = try JSONSerialization.data(withJSONObject: ["gql_data": ["shortcode_media": node]])
        let wrapper = try JSONSerialization.data(withJSONObject: ["contextJSON": String(decoding: context, as: UTF8.self)])
        return Data("<script>init(\(String(decoding: wrapper, as: UTF8.self)))</script>".utf8)
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let result = try await IGClient.resolve(.post(shortcode: "De8zYb_D6kT"))
            try check(result.items.count > 1, "Expected the public album, not just its preview")
            for item in result.items {
                let (data, response) = try await URLSession.shared.data(from: item.url)
                try check((response as? HTTPURLResponse)?.statusCode == 200 && !data.isEmpty,
                          "Media download failed")
            }
            print("Live public album: \(result.items.count) media files downloaded without login")
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let photo: [String: Any] = ["is_video": false, "display_url": "https://example.com/photo.jpg?a=1&b=2"]
        let video: [String: Any] = ["is_video": true, "display_url": "https://example.com/thumb.jpg",
                                    "video_url": "https://example.com/video.mp4"]
        var node = photo
        node["shortcode"] = "Example"
        node["owner"] = ["username": "public_account", "is_private": false]
        StubProtocol.body = try embed(node)
        let image = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
        try check(image.items.count == 1 && image.items[0].url.absoluteString == photo["display_url"] as? String,
                  "Public photo URL must survive JSON escaping")
        try check(StubProtocol.requests.count == 1 &&
                  StubProtocol.requests[0].url?.path == "/p/Example/embed/captioned" &&
                  StubProtocol.requests[0].value(forHTTPHeaderField: "Cookie") == nil,
                  "Public media must use the embed without login cookies")

        node["edge_sidecar_to_children"] = ["edges": [["node": photo], ["node": video]]]
        StubProtocol.body = try embed(node)
        let album = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
        try check(album.items.count == 2 && !album.items[0].isVideo && album.items[1].isVideo,
                  "Mixed albums must include photos and videos in order")

        var reel = video
        reel["shortcode"] = "Example"
        StubProtocol.body = try embed(reel)
        let resolvedReel = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
        try check(resolvedReel.kind == "Reel" && resolvedReel.items[0].isVideo, "Resolve public video")

        for status in [200, 401, 403, 429, 404] {
            StubProtocol.status = status
            StubProtocol.body = Data("<html>Log in to Instagram</html>".utf8)
            do {
                _ = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
                throw TestFailure(message: "Expected an error for status \(status)")
            } catch let error as IGError {
                switch (status, error) {
                case (200, .accessBlocked), (401, .accessBlocked), (403, .accessBlocked),
                     (429, .rateLimit), (404, .notFound): break
                default: throw TestFailure(message: "A blocked request must not be labelled private: \(error)")
                }
            }
        }
        StubProtocol.status = 200
        node["owner"] = ["username": "private_account", "is_private": true]
        StubProtocol.body = try embed(node)
        do {
            _ = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
            throw TestFailure(message: "Confirmed private media must require login")
        } catch IGError.loginRequired {}

        node["shortcode"] = "DifferentPost"
        StubProtocol.body = try embed(node)
        do {
            _ = try await IGClient.resolve(.post(shortcode: "Example"), session: session)
            throw TestFailure(message: "Must not return media for another post")
        } catch IGError.accessBlocked {}
        print("Passed: public photo, mixed album, video, blocked responses, private media, mismatched post")
    }
}
