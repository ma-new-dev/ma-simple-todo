import Foundation

struct LinkedInInfo {
    var name: String      = ""
    var jobTitle: String  = ""
    var company: String   = ""
    var city: String      = ""
    var headline: String  = ""
}

/// Fetches basic LinkedIn profile info by scraping the public page.
/// No API key required — works with copy-pasted LinkedIn URLs.
final class LinkedInService {
    static let shared = LinkedInService()

    enum LinkedInError: LocalizedError {
        case invalidURL
        case fetchFailed
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidURL:   return "Invalid LinkedIn URL."
            case .fetchFailed:  return "Could not load LinkedIn profile. Make sure the profile is public."
            case .parseError:   return "Could not parse profile info. Fill in manually."
            }
        }
    }

    func fetchBasicInfo(url: String) async throws -> LinkedInInfo {
        // Normalize URL
        var urlString = url.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http") { urlString = "https://" + urlString }
        guard let profileURL = URL(string: urlString) else { throw LinkedInError.invalidURL }

        // Build request with browser-like headers to load public profile HTML
        var request = URLRequest(url: profileURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LinkedInError.fetchFailed
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw LinkedInError.parseError
        }

        return parse(html: html)
    }

    // MARK: - HTML Parsing

    private func parse(html: String) -> LinkedInInfo {
        var info = LinkedInInfo()

        // Name — from <title> or og:title meta tag
        if let name = extract(html, pattern: #"<title[^>]*>([^<]+) \| LinkedIn</title>"#) {
            info.name = name.trimmingCharacters(in: .whitespaces)
        } else if let name = extract(html, pattern: #"<meta property="og:title" content="([^"]+)""#) {
            info.name = name.trimmingCharacters(in: .whitespaces)
        }

        // Headline / title — og:description often includes "Title at Company · Location"
        if let desc = extract(html, pattern: #"<meta property="og:description" content="([^"]+)""#) {
            let clean = desc.trimmingCharacters(in: .whitespaces)
            info.headline = clean

            // Parse "Job Title at Company" pattern
            let atParts = clean.components(separatedBy: " at ")
            if atParts.count >= 2 {
                info.jobTitle = atParts[0].trimmingCharacters(in: .whitespaces)
                // Company might be "Company · City, Country" — split on "·"
                let rest = atParts[1...].joined(separator: " at ")
                let dotParts = rest.components(separatedBy: " · ")
                info.company = dotParts[0].trimmingCharacters(in: .whitespaces)
                if dotParts.count > 1 {
                    // "City, Country" — take city portion
                    let location = dotParts[1].trimmingCharacters(in: .whitespaces)
                    info.city = location.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? location
                }
            }
        }

        // Fallback: try JSON-LD structured data
        if let jsonLD = extract(html, pattern: #"<script type="application/ld\+json">([\s\S]*?)</script>"#),
           let data = jsonLD.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = json["name"] as? String, info.name.isEmpty {
                info.name = name
            }
            if let jobTitle = json["jobTitle"] as? String, info.jobTitle.isEmpty {
                info.jobTitle = jobTitle
            }
            if let org = (json["worksFor"] as? [[String: Any]])?.first,
               let orgName = org["name"] as? String, info.company.isEmpty {
                info.company = orgName
            }
            if let address = json["address"] as? [String: Any],
               let locality = address["addressLocality"] as? String, info.city.isEmpty {
                info.city = locality
            }
        }

        return info
    }

    private func extract(_ html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captureRange])
    }
}
