import Foundation
import ImagePlayground
import SwiftData
import UIKit

/// Draws one picture per dish with Apple's Image Playground, on the device and free,
/// stores it as a `DishImage`, and reuses it every time the dish comes back. Requests run
/// one at a time. Image Playground only draws while the app is in the foreground and
/// needs Apple Intelligence; without it, cards keep their illustrated fallback.
@Observable
@MainActor
final class DishImageService {
    static let shared = DishImageService()

    private var inFlight: Set<String> = []
    private var queue: [(key: String, name: String)] = []
    private var isDraining = false
    /// Keys that failed this session; not retried until relaunch.
    private var failed: Set<String> = []
    private var creator: ImageCreator?
    /// Set once Image Playground says it can't run here, so we stop asking.
    private(set) var isUnsupported = false

    func image(for key: String, in context: ModelContext) -> DishImage? {
        var descriptor = FetchDescriptor<DishImage>(predicate: #Predicate { $0.dishKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Asks for a photo of `option` if none exists and none is on its way.
    func request(for option: MealOption, in context: ModelContext) {
        let key = option.dishKey
        guard !isUnsupported, !key.isEmpty, !inFlight.contains(key), !failed.contains(key),
              image(for: key, in: context)?.imageData == nil
        else { return }
        inFlight.insert(key)
        queue.append((key, option.name))
        drain(into: context)
    }

    private func drain(into context: ModelContext) {
        guard !isDraining else { return }
        isDraining = true
        Task {
            while !queue.isEmpty {
                let job = queue.removeFirst()
                do {
                    if let data = try await generate(name: job.name) {
                        context.insert(DishImage(dishKey: job.key, imageData: data))
                        try? context.save()
                    } else {
                        failed.insert(job.key)
                    }
                    inFlight.remove(job.key)
                } catch {
                    // The app went to the background: drop the queue; the cards ask
                    // again next time they appear.
                    queue.removeAll()
                    inFlight.removeAll()
                }
            }
            isDraining = false
        }
    }

    // MARK: - Image Playground

    /// nil when this dish can't be drawn; throws only when the app left the foreground.
    private func generate(name: String) async throws -> Data? {
        do {
            let creator = try await imageCreator()
            let styles = creator.availableStyles
            guard let style = [ImagePlaygroundStyle.illustration, .animation, .sketch].first(where: styles.contains) else {
                isUnsupported = true
                return nil
            }
            let concepts: [ImagePlaygroundConcept] = [
                .text("\(name), a home-cooked Indian vegetarian meal served on a plate, seen from above"),
            ]
            for try await image in creator.images(for: concepts, style: style, limit: 1) {
                return Self.downscaledJPEG(image.cgImage)
            }
            return nil
        } catch ImageCreator.Error.notSupported, ImageCreator.Error.unavailable {
            isUnsupported = true
            return nil
        } catch ImageCreator.Error.backgroundCreationForbidden {
            throw ImageCreator.Error.backgroundCreationForbidden
        } catch {
            return nil
        }
    }

    private func imageCreator() async throws -> ImageCreator {
        if let creator { return creator }
        let made = try await ImageCreator()
        creator = made
        return made
    }

    /// ~512 px JPEG: plenty for a card, and small enough to sync through CloudKit.
    static func downscaledJPEG(_ image: CGImage, maxPixelSize: CGFloat = 512) -> Data? {
        let scale = min(1, maxPixelSize / CGFloat(max(image.width, image.height)))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
