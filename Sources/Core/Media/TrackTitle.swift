import Foundation

/// A track's title as shown: the song's name, with the release details players
/// append ("- 2011 Remaster", "(feat. …)", "[Live]") split off so they can sit
/// small beside it instead of filling the headline.
struct TrackTitle: Equatable {
    let name: String
    /// The details, joined with " · ", or nil when there are none.
    let detail: String?
    /// The details one by one, as they appeared ("feat. X", "2011 Remaster").
    let details: [String]

    /// Words that mark a suffix as release details rather than part of the name.
    private static let markers = #"remaster|master|edit|live|acoustic|mono|stereo|version|mix|demo|session|edition|bonus|instrumental|recorded|anniversary|deluxe"#

    init(_ title: String) {
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var details: [String] = []
        // Repeat, so "Song (feat. X) - Remastered" loses both, from the end inward.
        while true {
            if let match = name.range(of: #"\s+[-–—]\s+([^-–—]+)$"#, options: .regularExpression),
               Self.isDetail(String(name[match]).trimmingCharacters(in: CharacterSet(charactersIn: " -–—"))) {
                details.insert(String(name[match]).trimmingCharacters(in: CharacterSet(charactersIn: " -–—")), at: 0)
                name = String(name[..<match.lowerBound])
                continue
            }
            if let match = name.range(of: #"\s*[\(\[]([^\(\)\[\]]+)[\)\]]$"#, options: .regularExpression) {
                let inner = String(name[match]).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]"))
                if Self.isDetail(inner) || Self.isFeature(inner) {
                    details.insert(inner, at: 0)
                    name = String(name[..<match.lowerBound])
                    continue
                }
            }
            break
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never leave nothing to show.
        if name.isEmpty {
            self.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.detail = nil
            self.details = []
        } else {
            self.name = name
            self.detail = details.isEmpty ? nil : details.joined(separator: " · ")
            self.details = details
        }
    }

    /// An album's name without its release details, so the artist line fits:
    /// "Hidden in Pieces: Live at the Royal Albert Hall" → "Hidden in Pieces",
    /// "(What's the Story) Morning Glory? (Deluxe Remastered Edition)" → "(What's the Story) Morning Glory?",
    /// "Seasons - Single" → "Seasons", "The Runner (Original Soundtrack)" → "The Runner".
    static func album(_ album: String) -> String {
        var name = album.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dash = name.range(of: #"\s+[-–—]\s+(?:single|ep)$"#, options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<dash.lowerBound])
        }
        name = TrackTitle(name).name
        if let score = name.range(of: #"\s*[\(\[][^\(\)\[\]]*(?:soundtrack|motion picture|original score)[^\(\)\[\]]*[\)\]]$"#,
                                  options: [.regularExpression, .caseInsensitive]) {
            name = String(name[..<score.lowerBound])
        }
        if let colon = name.range(of: ": "), isDetail(String(name[colon.upperBound...])) {
            name = String(name[..<colon.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? album : name
    }

    private static func isDetail(_ text: String) -> Bool {
        text.range(of: #"\b(?:\#(markers))"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isFeature(_ text: String) -> Bool {
        text.range(of: #"^(?:feat\.?|ft\.|featuring|with)\s"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// An artist credit split for display: the main artist as written (never broken
/// up, so "Simon & Garfunkel" and "Earth, Wind & Fire" stay whole) and the
/// featured artists, from "A feat. B", "A ft. B", "A featuring B" or "A (feat. B)"
/// / "A (with B)". A bare "with" is left alone, since band names use it.
struct ArtistCredit: Equatable {
    let main: String
    /// Each featured credit as written ("Rick Ross & Anderson .Paak").
    let featured: [String]

    init(_ credit: String) {
        var main = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        var featured: [String] = []
        if let paren = main.range(of: #"\s*[\(\[](?:feat\.?|ft\.?|featuring|with)\s+[^\(\)\[\]]+[\)\]]"#,
                                  options: [.regularExpression, .caseInsensitive]) {
            featured.append(Self.stripLead(String(main[paren]).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]"))))
            main.removeSubrange(paren)
        }
        if let feat = main.range(of: #"\s+(?:feat\.?|ft\.?|featuring)\s+"#, options: [.regularExpression, .caseInsensitive]) {
            featured.insert(String(main[feat.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines), at: 0)
            main = String(main[..<feat.lowerBound])
        }
        self.main = main.trimmingCharacters(in: .whitespacesAndNewlines)
        self.featured = featured.filter { !$0.isEmpty }
    }

    /// "feat. X" → "X" (also ft., featuring, with).
    static func stripLead(_ text: String) -> String {
        text.replacingOccurrences(of: #"^(?:feat\.?|ft\.?|featuring|with)\s+"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A name with a spaced dash is one artist, the stage name then the real one
    /// ("Lucy - Cooper B. Handy"): the short form keeps the stage name ("Lucy").
    /// Unspaced hyphens ("Jay-Z", "Sleater-Kinney") are untouched.
    static func short(_ credit: String) -> String {
        let shortened = credit.replacingOccurrences(of: #"\s+[-–—]\s+[^,&;/]*[^,&;/\s]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return shortened.isEmpty ? credit : shortened
    }
}

/// What's playing, sorted into proper fields however the player wrote it: the song's
/// name, its main artist and featured artists (from the artist's "feat." or "(feat. B)"
/// or the title's "(feat. B)", "(with B)" or "feat. B"), the album without edition
/// details, and the version ("Live", "Remastered 2011", "Acoustic", "Radio Edit"…), so
/// every view shows them the same way. Display only: lookups use the player's strings.
struct TrackMetadata: Equatable {
    let song: String
    /// The main artist or artists, as the player wrote them.
    let artist: String
    /// Featured credits as written, without repeats of the main artist.
    let featured: [String]
    /// nil when there's none, or it only repeats the song or artist.
    let album: String?
    let versions: [String]

    init(title: String, artist: String, album: String) {
        let parsed = TrackTitle(title)
        var song = parsed.name
        let credit = ArtistCredit(artist)
        self.artist = credit.main
        var featured = credit.featured
        var versions: [String] = []
        for detail in parsed.details {
            if TrackTitle.isFeature(detail) {
                featured.append(ArtistCredit.stripLead(detail))
            } else {
                versions.append(Self.version(detail))
            }
        }
        // "Song feat. B" without brackets ("ft." and "with" alone stay: "6 Ft. 7 Ft.", "Dancing with Myself").
        if let feat = song.range(of: #"\s+(?:feat\.|featuring)\s+\S"#, options: [.regularExpression, .caseInsensitive]),
           feat.lowerBound > song.startIndex {
            featured.append(ArtistCredit.stripLead(String(song[feat.lowerBound...]).trimmingCharacters(in: .whitespaces)))
            song = String(song[..<feat.lowerBound])
        }
        self.song = song
        // No repeats: a credit whose names are all already credited goes.
        var seen = Set(Self.names(credit.main).map { $0.lowercased() })
        self.featured = featured.filter { feature in
            let names = Self.names(feature).map { $0.lowercased() }
            guard !names.isEmpty, !names.allSatisfy(seen.contains) else { return false }
            seen.formUnion(names)
            return true
        }
        // An album named for its live recording says so when the song doesn't.
        if versions.isEmpty, album.range(of: #"\blive\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
           album.range(of: #"(?:[:(\[]|[-–—]\s).*\blive\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            versions = ["Live"]
        }
        self.versions = versions
        let short = TrackTitle.album(album)
        let repeats = short.isEmpty || [song, artist, credit.main, title].contains { short.caseInsensitiveCompare($0) == .orderedSame }
        self.album = repeats ? nil : short
    }

    /// The artist line's first part, never cut: "Yeah Yeah Yeahs", "A, B & C".
    var artistLine: String { artist }

    /// The featured artists for the small tag beside the title, stage names only:
    /// "Lucy", "Rick Ross & Anderson .Paak"; nil when nobody is featured.
    var featuredLabel: String? {
        featured.isEmpty ? nil : featured.map(ArtistCredit.short).joined(separator: " & ")
    }

    /// The artist, then the album: "Yeah Yeah Yeahs · Hidden in Pieces".
    var byline: String { [artistLine, album ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }

    /// Splits "A, B & C", "A x B", "A / B" into names, only to recognise repeats
    /// ("and" is left alone: band names use it). Display never splits a credit.
    static func names(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;/&"))
            .flatMap { $0.components(separatedBy: " x ") }
            .flatMap { $0.components(separatedBy: " X ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A version as a short tag: "2011 Remaster" → "Remastered 2011", "Live at the
    /// Royal Albert Hall" → "Live", "Radio Edit" stays.
    static func version(_ detail: String) -> String {
        let text = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"\blive\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "Live" }
        if text.range(of: #"remaster"#, options: .caseInsensitive) != nil || text.range(of: #"\bmaster\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let year = text.range(of: #"\b(?:19|20)\d\d\b"#, options: .regularExpression).map { " " + text[$0] } ?? ""
            return "Remastered" + year
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
