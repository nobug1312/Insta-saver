import SwiftUI
import AVKit

struct MediaPreview: View {
    let items: [MediaItem]
    @Binding var selected: Set<UUID>
    @State private var currentID: UUID
    @Environment(\.dismiss) private var dismiss

    init(items: [MediaItem], initialItem: MediaItem, selected: Binding<Set<UUID>>) {
        self.items = items
        _selected = selected
        _currentID = State(initialValue: initialItem.id)
    }

    private var index: Int { items.firstIndex { $0.id == currentID } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(index + 1) of \(items.count)")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("previewCounter")
                Spacer()
                Button { dismiss() } label: {
                    Label("Done", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color.termSurface, in: Capsule())
                }
                .accessibilityIdentifier("closePreview")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    Group {
                        if item.isVideo {
                            VideoPreview(url: item.url, active: currentID == item.id)
                                .simultaneousGesture(DragGesture().onEnded { value in
                                    if value.translation.height > 100 &&
                                        value.translation.height > abs(value.translation.width) * 1.5 {
                                        dismiss()
                                    }
                                })
                        } else {
                            PhotoPreview(item: item, onDismiss: { dismiss() })
                        }
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentID) {
                if !items[index].isVideo {
                    _ = await ThumbnailStore.preview.image(for: items[index].url)
                }
                guard !Task.isCancelled else { return }
                for neighbour in [index + 1, index - 1] where items.indices.contains(neighbour) {
                    guard !Task.isCancelled else { return }
                    let item = items[neighbour]
                    if !item.isVideo { _ = await ThumbnailStore.preview.image(for: item.url) }
                }
            }

            VStack(spacing: 12) {
                Text("Swipe to browse · Swipe down to close")
                    .font(.caption)
                    .foregroundStyle(Color.termDim)
                    .multilineTextAlignment(.center)
                Button {
                    selected.formSymmetricDifference([currentID])
                } label: {
                    Text(selected.contains(currentID) ? "[x] Selected for saving" : "[ ] Select for saving")
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.monospaced)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Color.termInk)
                        .background(Color.termIce, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("previewSelection")
            }
            .padding(20)
        }
        .foregroundStyle(Color.termFG)
        .background(Color.termBG.ignoresSafeArea())
    }
}

private struct PhotoPreview: View {
    let item: MediaItem
    let onDismiss: () -> Void
    @State private var image: UIImage?
    @State private var thumbnail: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ZStack {
            if let thumbnail, image == nil {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
            if let image {
                ZoomablePhoto(image: image, onDismiss: onDismiss)
                    .accessibilityLabel("Full-size photo. Pinch or double-tap to zoom.")
                    .accessibilityIdentifier("fullSizePhoto")
            } else if failed {
                ContentUnavailableView {
                    Label("Photo unavailable", systemImage: "photo")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { attempt += 1 }
                        .frame(minHeight: 44)
                }
            } else {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView().tint(.termIce)
                        Text("Loading photo…").font(.caption.monospaced())
                    }
                    .padding(12)
                    .background(Color.termBG.opacity(0.85), in: Capsule())
                    .padding(.bottom, 20)
                }
                .accessibilityLabel("Loading full-size photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            thumbnail = await ThumbnailStore.shared.image(for: item.thumb ?? item.url)
        }
        .task(id: attempt) {
            failed = false
            let loaded = await ThumbnailStore.preview.image(for: item.url)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}

private struct VideoPreview: View {
    let url: URL
    let active: Bool
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
            .onChange(of: active) { _, isActive in
                if !isActive { player?.pause() }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> PhotoScrollView { PhotoScrollView(image: image, onDismiss: onDismiss) }
    func updateUIView(_ uiView: PhotoScrollView, context: Context) { uiView.onDismiss = onDismiss }

    final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
        private let photo: UIImageView
        private var previousSize = CGSize.zero
        var onDismiss: () -> Void
        private let swipeDelegate = DismissGestureDelegate()

        init(image: UIImage, onDismiss: @escaping () -> Void) {
            photo = UIImageView(image: image)
            self.onDismiss = onDismiss
            super.init(frame: .zero)
            delegate = self
            maximumZoomScale = 4
            bounces = false
            alwaysBounceHorizontal = false
            alwaysBounceVertical = false
            isScrollEnabled = false
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            photo.contentMode = .scaleAspectFit
            addSubview(photo)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(closeViewer))
            swipe.direction = .down
            swipeDelegate.scrollView = self
            swipe.delegate = swipeDelegate
            addGestureRecognizer(swipe)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != previousSize {
                previousSize = bounds.size
                zoomScale = 1
                photo.frame = CGRect(origin: .zero, size: bounds.size)
                contentSize = bounds.size
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            isScrollEnabled = zoomScale > minimumZoomScale + 0.01
            accessibilityValue = "\(Int((zoomScale * 100).rounded()))%"
        }

        @objc private func closeViewer() { onDismiss() }

        @objc private func toggleZoom(_ tap: UITapGestureRecognizer) {
            if zoomScale > 1 {
                setZoomScale(1, animated: true)
            } else {
                let point = tap.location(in: photo)
                let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
                zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                width: size.width, height: size.height), animated: true)
            }

        }
    }

    private final class DismissGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var scrollView: UIScrollView?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView else { return false }
            return scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
