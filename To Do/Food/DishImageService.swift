import Foundation
import ImageIO
import SwiftData
import UIKit

/// Draws one photo per dish with OpenAI's image API, stores it as a `DishImage`, and
/// reuses it every time the dish comes back. Requests run one at a time so a fresh day of
/// twelve cards doesn't fire twelve parallel calls. Without a key, cards show their
/// illustrated fallback and nothing is requested.
@Observable
@MainActor
final class DishImageService {
    static let shared = DishImageService()

    private static let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    private static let model = "gpt-image-1"

    private var inFlight: Set<String> = []
    private var queue: [(key: String, name: String, detail: String)] = []
    private var isDraining = false
    /// Keys that failed this session; not retried until relaunch.
    private var failed: Set<String> = []

    var hasKey: Bool { KeychainStore.get(.imageAPIKey) != nil }

    func image(for key: String, in context: ModelContext) -> DishImage? {
        var descriptor = FetchDescriptor<DishImage>(predicate: #Predicate { $0.dishKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Asks for a photo of `option` if none exists and none is on its way.
    func request(for option: MealOption, in context: ModelContext) {
        let key = option.dishKey
        guard hasKey, !key.isEmpty, !inFlight.contains(key), !failed.contains(key),
              image(for: key, in: context)?.imageData == nil
        else { return }
        inFlight.insert(key)
        queue.append((key, option.name, option.detail))
        drain(into: context)
    }

    private func drain(into context: ModelContext) {
        guard !isDraining else { return }
        isDraining = true
        Task {
            while !queue.isEmpty {
                let job = queue.removeFirst()
                if let data = await generate(name: job.name, detail: job.detail) {
                    context.insert(DishImage(dishKey: job.key, imageData: data))
                    try? context.save()
                } else {
                    failed.insert(job.key)
                }
                inFlight.remove(job.key)
            }
            isDraining = false
        }
    }

    // MARK: - Network

    private func generate(name: String, detail: String) async -> Data? {
        guard let key = KeychainStore.get(.imageAPIKey) else { return nil }
        let prompt = """
        Overhead food photograph of a home-cooked Indian meal: \(name). \(detail). \
        Served on a simple ceramic plate or steel thali on a light wooden table, soft \
        natural window light, realistic home portion, no text, no hands, no cutlery clutter.
        """
        let body: [String: Any] = [
            "model": Self.model,
            "prompt": prompt,
            "size": "1024x1024",
            "quality": "low",
            "n": 1,
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(ImageResponse.self, from: data)
            guard let b64 = decoded.data.first?.b64Json, let raw = Data(base64Encoded: b64) else { return nil }
            return Self.downscaledJPEG(raw)
        } catch {
            return nil
        }
    }

    private struct ImageResponse: Decodable {
        struct Item: Decodable {
            let b64Json: String?
            enum CodingKeys: String, CodingKey { case b64Json = "b64_json" }
        }
        let data: [Item]
    }

    /// ~512 px JPEG: plenty for a card, and small enough to sync through CloudKit.
    static func downscaledJPEG(_ data: Data, maxPixelSize: CGFloat = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.75)
    }
}
