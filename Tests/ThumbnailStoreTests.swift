import XCTest
import UIKit

private final class ImageProtocol: URLProtocol {
    static var data = Data()
    static var status = 200
    private static let lock = NSLock()
    private static var count = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    static func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ThumbnailStoreTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageProtocol.self]
        session = URLSession(configuration: config)
        ImageProtocol.reset()
        ImageProtocol.status = 200
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        ImageProtocol.data = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            }
    }

    override func tearDown() { session.invalidateAndCancel() }

    func testDownsamplesAndReusesDecodedImageAcrossLoads() async throws {
        let store = ThumbnailStore(session: session)
        let url = URL(string: "https://example.com/photo.jpg")!
        async let first = store.image(for: url)
        async let second = store.image(for: url)
        let (a, b) = await (first, second)
        let image = try XCTUnwrap(a)
        XCTAssertEqual(image.cgImage?.width, 640)
        XCTAssertEqual(image.cgImage?.height, 480)
        XCTAssertTrue(image === b)
        let cached = await store.image(for: url)
        XCTAssertTrue(image === cached)
        XCTAssertEqual(ImageProtocol.requestCount, 1)
    }

    func testFailedDownloadCanBeRetried() async {
        let store = ThumbnailStore(session: session)
        let url = URL(string: "https://example.com/retry.jpg")!
        ImageProtocol.status = 403
        let failed = await store.image(for: url)
        XCTAssertNil(failed)
        ImageProtocol.status = 200
        let recovered = await store.image(for: url)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(ImageProtocol.requestCount, 2)
    }

    func testViewerCacheKeepsMoreDetailThanGrid() async throws {
        let url = URL(string: "https://example.com/preview.jpg")!
        let store = ThumbnailStore(session: session, maxPixelSize: 2048)
        let loaded = await store.image(for: url)
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.cgImage?.width, 1600)
        XCTAssertEqual(image.cgImage?.height, 1200)
        let cached = await store.image(for: url)
        XCTAssertTrue(image === cached)
        XCTAssertEqual(ImageProtocol.requestCount, 1)
    }
}
