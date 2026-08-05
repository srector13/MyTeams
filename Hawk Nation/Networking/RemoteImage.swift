//
//  RemoteImage.swift
//  myTeams
//
//  A dependency-free replacement for SDWebImageSwiftUI, Kingfisher and
//  AlamofireImage.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "images")

/// An in-memory cache for decoded images, layered over a private URL cache.
///
/// The rosters and schedules put the same headshots and team logos on screen
/// many times over, and the horizontal carousels recycle them as they scroll.
/// A `URLCache` alone would avoid the network but still decode on every pass,
/// so decoded images are held here too.
private actor ImageCache {
    static let shared = ImageCache()

    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    /// In-flight downloads, so that many views asking for the same logo at the
    /// same moment share a single request.
    private var loads: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL, reloading: Bool = false) async -> UIImage? {
        if !reloading, let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = loads[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> { [session] in
            var request = URLRequest(url: url)
            if reloading {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            }
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return UIImage(data: data)
            } catch {
                logger.debug("Image load failed for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
        loads[url] = task

        let image = await task.value
        loads[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

/// The flat grey fill shown across the roster, schedule and news lists while
/// an image loads. It occupies the same space the image eventually will.
struct RemoteImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .systemGray4))
    }
}

/// Displays a resizable image loaded from the network, showing `placeholder`
/// until it arrives.
///
/// Stands in for the third-party `WebImage`: it caches, it coalesces
/// concurrent requests for the same URL, and it shows a spinner over the
/// placeholder while loading. The image is already resizable, so call sites
/// apply `.scaledToFit()`, `.frame(…)` and friends directly.
struct RemoteImage<Placeholder: View>: View {
    private enum Phase {
        case loading
        case loaded(UIImage?)
    }

    private let url: URL?
    private let reloading: Bool
    private let placeholder: Placeholder

    @State private var phase: Phase = .loading

    init(
        url: URL?,
        reloading: Bool = false,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.reloading = reloading
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if case .loaded(let image?) = phase {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder
                    .overlay {
                        if url != nil, case .loading = phase {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: url) {
            guard let url else {
                phase = .loaded(nil)
                return
            }
            phase = .loading
            phase = .loaded(await ImageCache.shared.image(for: url, reloading: reloading))
        }
    }
}

extension RemoteImage where Placeholder == RemoteImagePlaceholder {
    init(url: URL?, reloading: Bool = false) {
        self.init(url: url, reloading: reloading) { RemoteImagePlaceholder() }
    }

    /// Convenience for the many call sites that hold their URL as a string.
    init(url string: String, reloading: Bool = false) {
        self.init(url: URL(string: string), reloading: reloading)
    }
}
