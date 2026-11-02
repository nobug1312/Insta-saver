import Photos

enum Downloader {
    struct PermissionError: LocalizedError {
        var errorDescription: String? { "Allow access to Photos in Settings to save media." }
    }

    static func save(_ item: MediaItem) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PermissionError() }

        let (tmp, _) = try await URLSession.shared.download(from: item.url)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(item.isVideo ? "mp4" : "jpg")
        try FileManager.default.moveItem(at: tmp, to: dest)
        defer { try? FileManager.default.removeItem(at: dest) }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset()
                .addResource(with: item.isVideo ? .video : .photo, fileURL: dest, options: nil)
        }
    }
}
