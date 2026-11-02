import UIKit
import ImageIO

actor ThumbnailStore {
    static let shared = ThumbnailStore()
    static let preview = ThumbnailStore(maxPixelSize: 2048, memoryLimit: 48 * 1024 * 1024)

    private let cache = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    private let maxPixelSize: Int

    init(session: URLSession = .shared, maxPixelSize: Int = 640, memoryLimit: Int = 24 * 1024 * 1024) {
        self.session = session
        self.maxPixelSize = maxPixelSize
        cache.totalCostLimit = memoryLimit
        cache.countLimit = 80
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = pending[url] { return await task.value }
        // Decoding runs on this actor, not the main actor. Shared work survives a cell scrolling offscreen.
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(data as CFData, [
                    kCGImageSourceShouldCache: false
                  ] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            let image = UIImage(cgImage: thumbnail)
            cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            return image
        }
        pending[url] = task
        let image = await task.value
        pending[url] = nil
        return image
    }
}
