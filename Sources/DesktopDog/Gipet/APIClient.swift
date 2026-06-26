// Gipet — thin networking layer (mirrors Git Streaks' `APIClient`).

import Foundation

enum APIError: Error, CustomStringConvertible {
    case badURL
    case http(Int)
    case empty
    case decode(String)

    var description: String {
        switch self {
        case .badURL:          return "bad url"
        case .http(let code):  return "http \(code)"
        case .empty:           return "empty response"
        case .decode(let why): return "decode error: \(why)"
        }
    }
}

/// Minimal async HTTP wrapper. Adds the GitHub token when present.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    var accessToken: String?

    // Per-URL ETag cache so high-frequency contribution polls send
    // `If-None-Match` and get a cheap 304 when nothing changed — polite to
    // GitHub and lowers the chance of tripping its abuse rate limit.
    private var etagCache: [String: (etag: String, body: String)] = [:]
    private let etagLock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch raw text (used for the contributions HTML page). Transparently
    /// revalidates with the stored ETag: on a 304 it returns the cached body,
    /// otherwise it caches the fresh body + new ETag.
    func text(_ url: URL, accept: String = "text/html") async throws -> String {
        let key = url.absoluteString
        let cached = cachedETag(key)

        var req = URLRequest(url: url)
        // Bypass URLSession's own cache so our manual conditional request is the
        // one that reaches the origin (and we actually see the 304).
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("Gipet", forHTTPHeaderField: "User-Agent")
        if let cached { req.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 304, let cached { return cached.body }   // unchanged
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
            guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { throw APIError.empty }
            if let etag = http.value(forHTTPHeaderField: "Etag") {
                storeETag(key, (etag, s))
            }
            return s
        }
        guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { throw APIError.empty }
        return s
    }

    // Synchronous lock helpers — keep NSLock out of the async `text` body
    // (locking across an await is unsafe; the compiler enforces this in Swift 6).
    private func cachedETag(_ key: String) -> (etag: String, body: String)? {
        etagLock.lock(); defer { etagLock.unlock() }
        return etagCache[key]
    }
    private func storeETag(_ key: String, _ value: (etag: String, body: String)) {
        etagLock.lock(); defer { etagLock.unlock() }
        etagCache[key] = value
    }

    /// Fetch + decode JSON, sending `Authorization: Bearer <token>` if set.
    func json<T: Decodable>(_ type: T.Type, _ url: URL,
                            authorized: Bool = true) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Gipet", forHTTPHeaderField: "User-Agent")
        if authorized, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(String(describing: error))
        }
    }

    /// POST form/JSON and decode the JSON reply (used for the token exchange).
    func post<T: Decodable>(_ type: T.Type, _ url: URL,
                            form: [String: String]) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Gipet", forHTTPHeaderField: "User-Agent")
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(String(describing: error))
        }
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=?+")
        return cs
    }()
}
