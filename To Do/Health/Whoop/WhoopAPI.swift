import Foundation

/// Low-level HTTP against the WHOOP v2 API. No state, no tokens of its own.
enum WhoopAPI {
    static let host = "https://api.prod.whoop.com"
    static let authorizeURL = "\(host)/oauth/oauth2/auth"
    static let tokenURL = "\(host)/oauth/oauth2/token"
    /// Kept from Baseline on purpose: it is the redirect already registered in the WHOOP
    /// developer dashboard, so Compass needs no dashboard change. ASWebAuthenticationSession
    /// captures its own callback, so this works even while Baseline is still installed.
    static let redirectURI = "baseline://whoop/callback"
    static let callbackScheme = "baseline"

    /// `offline` is not a dashboard scope — it is requested here, at runtime, and is
    /// what makes WHOOP issue a refresh token at all.
    static let scopes = [
        "read:recovery",
        "read:sleep",
        "read:cycles",
        "read:workout",
        "read:body_measurement",
        "read:profile",
        "offline",
    ]

    // MARK: Paths

    enum Path: String {
        case recovery = "/developer/v2/recovery"
        case sleep = "/developer/v2/activity/sleep"
        case cycle = "/developer/v2/cycle"
        case workout = "/developer/v2/activity/workout"
        case bodyMeasurement = "/developer/v2/user/measurement/body"
    }

    // MARK: Decoding

    static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised date format: \(raw)"
            )
        }
        return decoder
    }()

    // MARK: Token exchange

    /// Both the authorization-code exchange and the refresh go through here.
    /// Form-encoded per RFC 6749.
    static func postToken(fields: [String: String]) async throws -> WhoopTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        do {
            return try JSONDecoder().decode(WhoopTokenResponse.self, from: data)
        } catch {
            throw WhoopError.decoding(String(describing: error))
        }
    }

    // MARK: Authenticated reads

    /// Every record since `start`, following WHOOP's page tokens (25 per page). Capped
    /// at `maxPages` so a bad token can't loop forever.
    static func getAll<Record: Decodable>(
        _ path: Path,
        of type: Record.Type,
        start: Date,
        token: String,
        maxPages: Int = 12
    ) async throws -> [Record] {
        var records: [Record] = []
        var next: String?
        for _ in 0..<maxPages {
            let page = try await getPage(path, of: type, start: start, nextToken: next, token: token)
            records += page.records
            guard let token = page.nextToken, !token.isEmpty else { break }
            next = token
        }
        return records
    }

    static func getPage<Record: Decodable>(
        _ path: Path,
        of: Record.Type,
        limit: Int = 25,
        start: Date? = nil,
        nextToken: String? = nil,
        token: String
    ) async throws -> WhoopPage<Record> {
        var components = URLComponents(string: host + path.rawValue)!
        var items = [URLQueryItem(name: "limit", value: String(min(limit, 25)))]
        if let start {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            items.append(URLQueryItem(name: "start", value: formatter.string(from: start)))
        }
        if let nextToken {
            items.append(URLQueryItem(name: "nextToken", value: nextToken))
        }
        components.queryItems = items

        let data = try await authorizedGet(url: components.url!, token: token)
        do {
            return try decoder.decode(WhoopPage<Record>.self, from: data)
        } catch {
            throw WhoopError.decoding(String(describing: error))
        }
    }

    static func getObject<T: Decodable>(_ path: Path, of: T.Type, token: String) async throws -> T {
        let data = try await authorizedGet(url: URL(string: host + path.rawValue)!, token: token)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WhoopError.decoding(String(describing: error))
        }
    }

    private static func authorizedGet(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return data
    }

    // MARK: Helpers

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw WhoopError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
