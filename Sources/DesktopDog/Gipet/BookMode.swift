// Gipet — LOCAL-ONLY "book mode" for the journal button.
//
// Normally the journal button appends an AI line to `gipet-journal.md`. When a
// book-source file is present in a watched repo, the button instead appends the
// next PARAGRAPH of that book to `gipet-journal.md` — one commit per paragraph —
// so over time the journal fills up with an entire book.
//
// App Sandbox note: the app can only read files inside folders the user granted
// via "Add Folder" (security-scoped bookmarks restored at launch). So the book
// source lives INSIDE the watched repo, as `.gipet-book.txt`, NOT in ~/ or the
// app bundle. Drop that file into a repo to turn book mode on for that repo;
// remove it to go back to the normal AI journal. Nothing ships in the app.
//
// Reset progress:  defaults delete com.gipet.app "gipet.book.index.<repo-path>"

import Foundation

/// Walks a plain-text book (one paragraph per commit) sourced from a file inside
/// the repo. Progress is stored per repo path in the app's own UserDefaults.
enum BookSource {

    /// Book-source file expected inside each repo. Hidden so it stays out of the
    /// way; add it to the repo's .gitignore so only the revealed journal commits.
    static let sourceFileName = ".gipet-book.txt"

    static func sourceURL(forRepo path: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent(sourceFileName)
    }

    /// Book mode runs for a repo only when its book-source file exists; otherwise
    /// callers fall back to the normal AI journal.
    static func isAvailable(forRepo path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: sourceURL(forRepo: path).path)
    }

    /// Paragraphs = runs of text separated by one or more blank lines.
    /// Internal single line breaks (word wrap) are preserved within a paragraph.
    static func paragraphs(forRepo path: String) -> [String] {
        guard let raw = try? String(contentsOf: sourceURL(forRepo: path), encoding: .utf8) else { return [] }
        return raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Progress (per repo)

    // Progress lives in a file INSIDE the repo (not UserDefaults) so it is both
    // sandbox-writable by the app and editable from outside — letting the book
    // be pre-seeded and resumed without the app double-writing paragraphs.
    static let progressFileName = ".gipet-book-progress"

    private static func progressURL(forRepo path: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent(progressFileName)
    }

    static func currentIndex(forRepo path: String) -> Int {
        guard let s = try? String(contentsOf: progressURL(forRepo: path), encoding: .utf8),
              let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return n
    }

    static func setIndex(_ i: Int, forRepo path: String) {
        try? "\(i)\n".write(to: progressURL(forRepo: path), atomically: true, encoding: .utf8)
    }
}
