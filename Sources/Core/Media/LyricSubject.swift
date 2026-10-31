import Foundation

/// What a line is clearly about, for the Scenes lyric style (`LyricStyle.stickers`):
/// each subject is one small drawn scene that plays out with the line. Pure, so
/// `check-lyrics` covers the choice; the app adds a cache and an on-device
/// meaning fallback for words in no list.
enum LyricSubject: String, CaseIterable, Sendable {
    case money, cards, crowd, dance, heart, heartbreak, rose, fire, rain, sun, moon, stars, drive, phone
    case ocean, city, crown, diamond, drink, smoke, time, plane, home, tears, music, snow, eyes
    case cup, sneakers, guitar, microphone

    /// Words that name each subject outright. One of these is enough to draw it.
    static let strong: [LyricSubject: [String]] = [
        .money: ["money", "cash", "coin", "coins", "dollar", "dollars", "bucks", "pennies", "penny", "dimes", "paid", "payday",
                 "rich", "riches", "wealth", "fortune", "millionaire", "billionaire", "wallet", "benjamins", "guap", "bankroll", "banknotes"],
        .cards: ["cards", "card", "deck", "poker", "aces", "ace", "gamble", "gambling", "gambler", "casino", "jackpot",
                 "blackjack", "dice", "joker"],
        .crowd: ["crowd", "crowds", "audience", "stadium", "festival", "concert", "arena", "fans", "cheering"],
        .dance: ["dance", "dancing", "danced", "dancer", "dancers", "dancefloor", "disco", "nightclub", "party", "partying"],
        .heart: ["heart", "hearts", "heartbeat", "valentine"],
        .heartbreak: ["heartbreak", "heartbroken", "heartache", "brokenhearted"],
        .rose: ["roses", "flower", "flowers", "bloom", "blooming", "petal", "petals", "bouquet", "blossom", "daisy",
                "daisies", "tulips", "lilies"],
        .fire: ["fire", "fires", "flame", "flames", "burn", "burning", "burned", "burnt", "blaze", "ablaze", "lighter", "inferno"],
        .rain: ["rain", "raining", "rained", "rainy", "raindrops", "storm", "storms", "stormy", "thunder", "downpour",
                "drizzle", "umbrella", "puddles"],
        .sun: ["sun", "sunshine", "sunrise", "sunlight", "sunny", "summer", "daylight", "sunset"],
        .moon: ["moon", "moonlight", "midnight", "crescent"],
        .stars: ["star", "stars", "starlight", "starry", "constellation", "constellations", "galaxy", "comet"],
        .drive: ["car", "cars", "highway", "freeway", "interstate", "wheels", "engine", "backseat", "headlights",
                 "taillights", "rearview", "cadillac", "convertible", "traffic", "speeding", "coupe", "benz", "mercedes", "ferrari", "lambo", "limousine", "motorcycle", "truck"],
        .phone: ["phone", "phones", "cellphone", "telephone", "voicemail", "hotline", "texts", "dial"],
        .ocean: ["ocean", "oceans", "sea", "seas", "waves", "tide", "tides", "surf", "surfing", "beach"],
        .city: ["city", "cities", "skyline", "downtown", "skyscraper", "skyscrapers", "neon", "rooftop", "rooftops", "buildings"],
        .crown: ["crown", "crowned", "king", "kings", "queen", "queens", "throne", "royal", "royalty", "kingdom", "prince", "princess"],
        .diamond: ["diamond", "diamonds", "jewel", "jewels", "jewelry", "jewellery", "gem", "gems", "bling", "necklace", "pendant", "bracelet", "earrings"],
        .drink: ["wine", "whiskey", "whisky", "champagne", "cheers", "bottle", "tequila", "vodka", "liquor", "bourbon",
                 "beer", "cocktail", "cocktails", "drunk"],
        .smoke: ["smoke", "smoking", "smoked", "cigarette", "cigarettes", "cigar", "cigars", "blunts", "spliff"],
        .time: ["clock", "clocks", "oclock", "ticking", "tick", "tock", "hourglass", "countdown"],
        .plane: ["plane", "planes", "airplane", "airplanes", "jet", "airport", "flight", "flights", "pilot", "runway", "takeoff"],
        .home: ["home", "house", "hometown", "porch"],
        .tears: ["tears", "teardrop", "teardrops", "cry", "crying", "cried", "cries", "weep", "weeping", "sobbing"],
        .music: ["song", "songs", "music", "melody", "vinyl", "radio", "playlist", "jukebox", "stereo", "speakers"],
        .snow: ["snow", "snowing", "snowflake", "snowflakes", "snowfall", "winter", "blizzard", "frost"],
        .eyes: ["eyes", "staring", "gaze", "gazing", "blink"],
        .cup: ["sprite", "doublecup"],
        .sneakers: ["sneaker", "sneakers", "jordans"],
        .guitar: ["guitar", "guitars", "fretboard", "sixstring"],
        .microphone: ["microphone", "microphones", "mic", "karaoke"],
    ]

    /// Common words that lean toward a subject but are usually something else in a
    /// lyric ("I love you", "lost track of time", "drive me crazy", "the sun rose").
    /// They only add to a subject another word already names, or count when three agree.
    static let weak: [LyricSubject: [String]] = [
        .money: ["gold", "million", "millions", "bills", "spend", "spent"],
        .cards: ["bet", "luck", "lucky", "vegas", "deal", "dealer"],
        .crowd: ["people", "everybody", "everyone", "hands", "cheer"],
        .dance: ["move", "moving", "groove", "floor", "club"],
        .heart: ["love", "loves", "loved", "loving", "lover", "beat", "beating"],
        .rose: ["rose", "garden"],
        .fire: ["spark", "sparks", "match", "light", "hot", "heat"],
        .rain: ["pouring", "wet", "grey", "gray", "clouds"],
        .sun: ["morning", "dawn", "bright", "golden"],
        .moon: ["night", "tonight", "dark", "nights"],
        .stars: ["shine", "shining", "sparkle", "wish", "sky"],
        .drive: ["drive", "driving", "drove", "ride", "riding", "road", "roads", "wheel", "passenger", "racing"],
        .phone: ["call", "calling", "called", "text", "ring", "ringing", "hello"],
        .ocean: ["water", "wave", "shore"],
        .city: ["streets", "street", "town", "lights"],
        .crown: ["empire", "rule", "gold"],
        .diamond: ["ice", "crystal", "shine"],
        .drink: ["drink", "drinks", "drinking", "glass", "toast", "shots", "bar", "wasted"],
        .smoke: ["ashes", "haze"],
        .time: ["time", "minute", "minutes", "hour", "hours", "seconds", "late", "alarm"],
        .plane: ["fly", "flying", "flew", "wings", "sky", "clouds"],
        .home: ["door", "roof", "kitchen"],
        .tears: ["tear", "sad"],
        .music: ["sing", "singing", "sang", "beat", "rhythm", "record", "records", "dj"],
        .snow: ["cold", "ice", "frozen", "december"],
        .eyes: ["look", "looking", "see", "watching", "stare", "glance"],
    ]

    /// Words that break a heart when they're within three words of "heart".
    static let breaking: Set<String> = ["break", "breaking", "broke", "broken", "breaks", "shattered", "cracked"]

    /// Slang needs a nearby supporting word or a specific phrase. These words are
    /// also withheld from the embedding fallback: bread isn't automatically cash.
    static let contextual: [LyricSubject: [String]] = [
        .cup: ["lean", "sip", "sips", "sipping", "sippin", "cup", "cups", "purple", "styrofoam"],
        .money: ["racks", "bands", "bread", "cheese", "stack", "stacks", "bag"],
        .smoke: ["blunt", "joint", "joints", "weed"],
        .sneakers: ["kicks", "trainers", "chucks"],
        .drive: ["whip"], .diamond: ["chain", "chains", "drip", "ice"],
        .city: ["hood", "block", "streets"], .dance: ["club"],
    ]

    private static let contextualWords = Set(contextual.values.flatMap { $0 })

    /// Context stays local (at most three intervening words), so unrelated clauses
    /// don't turn "lean on me" into a cup or a bicycle chain into jewellery.
    private static func contextualHits(_ ordered: [String]) -> [(LyricSubject, Int)] {
        var hits: [(LyricSubject, Int)] = []
        let beverages: Set<String> = ["tea", "coffee", "cocoa", "water"]
        for (index, word) in ordered.enumerated() {
            let nearby = Set(ordered[max(0, index - 4)..<min(ordered.count, index + 5)])
            func has(_ words: Set<String>) -> Bool { !nearby.isDisjoint(with: words) }
            let prefix = ordered[max(0, index - 3)..<index].joined(separator: " ")
            if contextual[.cup]!.contains(word), !has(beverages),
               (has(["sip", "sips", "sipping", "sippin"]) && has(["lean", "cup", "cups", "purple", "sprite"]) ||
                has(["cup", "cups"]) && has(["lean", "purple", "styrofoam"])) { hits.append((.cup, index)) }
            if contextual[.money]!.contains(word),
               !has(["eat", "eating", "bake", "baking", "sandwich", "grocery", "groceries", "luggage", "guitar", "rubber", "shelf", "shelves", "flour", "books", "dishes", "plates", "toast", "oven", "baggage", "suitcase"]),
               (has(["money", "cash", "dollars", "guap", "bankroll", "paid"]) ||
                has(["count", "counting", "countin", "stacking", "stackin"]) ||
                ["bread", "bag"].contains(word) && has(["chasing", "chasin", "getting", "gettin", "making", "makin"]) ||
                ["racks", "bands"].contains(word) && prefix.hasSuffix("\(word) on")) { hits.append((.money, index)) }
            if contextual[.smoke]!.contains(word), !has(["garden", "gardening", "elbow", "knee"]),
               has(["smoke", "smoking", "roll", "rolling", "rollin", "puff", "puffing", "lit", "ashtray"]) { hits.append((.smoke, index)) }
            if contextual[.sneakers]!.contains(word), !has(["personal", "gym", "coach"]),
               has(["wear", "wearing", "worn", "lace", "laces", "feet", "soles", "fresh"]) { hits.append((.sneakers, index)) }
            if word == "whip", !has(["cream", "whipped", "whipping"]),
               (has(["ride", "riding", "driving", "drive", "park", "parked", "pull", "pulling", "coupe", "benz"]) ||
                prefix.hasSuffix("in my") || prefix.hasSuffix("in the")) { hits.append((.drive, index)) }
            if contextual[.diamond]!.contains(word),
               !has(["bicycle", "bike", "chainsaw", "rain", "tap", "faucet", "melting", "melt", "skating", "skate", "cream", "snow"]),
               has(["neck", "wrist", "gold", "silver", "diamonds", "diamond", "bling", "jewelry", "jewellery"]) { hits.append((.diamond, index)) }
            let lastTwo = prefix.split(separator: " ").suffix(2).joined(separator: " ")
            if word == "streets" ||
               (word == "hood" && !has(["coat", "jacket", "engine"]) && ["in the", "from the", "in my", "round the"].contains(lastTwo)) ||
               (word == "block" && !has(["cheese", "wood", "stone"]) && ["on the", "round the", "on my"].contains(lastTwo)) {
                hits.append((.city, index))
            }
            if word == "club", !has(["book", "golf", "chess", "fight"]),
               (prefix.hasSuffix("in the") || prefix.hasSuffix("at the") || has(["dj", "dancing", "dancefloor"])) { hits.append((.dance, index)) }
        }
        return hits
    }

    private static let strongLookup = table(strong)
    private static let weakLookup = table(weak)

    private static func table(_ lists: [LyricSubject: [String]]) -> [String: [LyricSubject]] {
        var result: [String: [LyricSubject]] = [:]
        // allCases order, so a word in two lists ("gold", "shine") always votes the same way.
        for subject in allCases { for word in lists[subject] ?? [] { result[word, default: []].append(subject) } }
        return result
    }

    /// Lower-case words with apostrophes dropped ("don't" → "dont", "o'clock" → "oclock").
    static func words(_ line: String) -> [String] {
        line.lowercased().filter { $0 != "'" && $0 != "’" }
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    /// Whether any list knows the word (the meaning fallback skips those).
    static func listed(_ word: String) -> Bool { strongLookup[word] != nil || weakLookup[word] != nil || contextualWords.contains(word) }

    /// The subject a line is clearly about, or nil. Every distinct word votes for
    /// the subjects it names: a naming word 3, a common one 1, and 2 more when it's
    /// the poster's headline. A subject needs 3, so one naming word draws it but
    /// common words alone ("I love you tonight") never do. A tie goes to the
    /// headline's subject, then to the one named first. Better nothing than wrong.
    static func vote(_ line: String, hero: String) -> LyricSubject? {
        let ordered = words(Lyrics.asides(line).sung)
        // "break(ing) my heart", "my heart is broken": the two words close together.
        for (index, word) in ordered.enumerated() where word == "heart" || word == "hearts" {
            if ordered[max(0, index - 3)..<min(ordered.count, index + 4)].contains(where: breaking.contains) { return .heartbreak }
        }
        let headline = words(hero).first ?? ""
        var score: [LyricSubject: Int] = [:]
        var first: [LyricSubject: Int] = [:]
        var headlined = Set<LyricSubject>()
        var counted = Set<String>()
        for (index, word) in ordered.enumerated() where counted.insert(word).inserted {
            let isHero = word == headline
            for subject in strongLookup[word] ?? [] {
                score[subject, default: 0] += 3 + (isHero ? 2 : 0)
                if isHero { headlined.insert(subject) }
                if first[subject] == nil { first[subject] = index }
            }
            for subject in weakLookup[word] ?? [] where !contextualWords.contains(word) || subject == .snow && word == "ice" {
                score[subject, default: 0] += 1
                if first[subject] == nil { first[subject] = index }
            }
        }
        // One contextual match has the weight of a naming word; repeated cues don't
        // overpower a clearer subject elsewhere in the line.
        let context = Dictionary(grouping: contextualHits(ordered), by: { $0.0 })
        for subject in allCases {
            guard let hits = context[subject], let index = hits.map({ $0.1 }).min() else { continue }
            let isHero = hits.contains { ordered[$0.1] == headline }
            score[subject, default: 0] += 3 + (isHero ? 2 : 0)
            if isHero { headlined.insert(subject) }
            first[subject] = min(first[subject] ?? index, index)
        }
        let ranked = score.filter { $0.value >= 3 }.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            if headlined.contains(a.key) != headlined.contains(b.key) { return headlined.contains(a.key) }
            if first[a.key] != first[b.key] { return first[a.key]! < first[b.key]! }
            return allCases.firstIndex(of: a.key)! < allCases.firstIndex(of: b.key)!
        }
        return ranked.first?.key
    }

    /// The double cup is a specific drink image, so generic cup neighbours (coffee,
    /// teacup, mug) must never select it through word embeddings.
    static let meaningExcluded: Set<LyricSubject> = [.cup]

    /// One word that means each subject, for the meaning fallback.
    static let anchors: [LyricSubject: String] = [
        .money: "money", .cards: "cards", .crowd: "crowd", .dance: "dance", .heart: "heart", .heartbreak: "heartbreak",
        .rose: "flower", .fire: "fire", .rain: "rain", .sun: "sun", .moon: "moon", .stars: "star", .drive: "car",
        .phone: "phone", .ocean: "ocean", .city: "city", .crown: "crown", .diamond: "diamond", .drink: "wine",
        .smoke: "smoke", .time: "clock", .plane: "airplane", .home: "home", .tears: "tears", .music: "music",
        .snow: "snow", .eyes: "eyes", .cup: "cup", .sneakers: "sneaker", .guitar: "guitar", .microphone: "microphone",
    ]

    /// The meaning fallback accepts a word only this close to an anchor (cosine distance
    /// in Apple's word embedding): "lilac" → flower (0.78), "snowstorm" → snow (0.72),
    /// "brandy" → wine (0.75), while "forever" → heart (0.91), "feeling" → heartbreak
    /// (0.89) and vague neighbours stay out; named vehicles use the explicit list.
    static let meaningCutoff = 0.82

    /// Common words the meaning fallback never looks up.
    static let stopWords: Set<String> = [
        "that", "this", "with", "from", "your", "have", "what", "when", "where", "there", "their", "they", "them", "were",
        "just", "like", "know", "want", "never", "always", "could", "would", "should", "about", "into", "over", "back",
        "only", "then", "than", "been", "will", "some", "more", "much", "still", "even", "every", "cause", "gonna", "wanna",
        "gotta", "yeah", "baby", "thing", "things", "something", "nothing", "everything", "anything", "because", "without",
        "girl", "girls", "boy", "boys", "shawty", "shorty", "woman", "women", "man", "men",
        "another", "through", "though", "forever", "feeling", "feel", "mind", "tonight", "little", "around", "really",
    ]
}

/// When a scene enters, acts and is ready to leave, in seconds from the moment its
/// line shows, paced by the singing: words a second over the line's sung span
/// (Mood's `MoodTreatment.wordsPerSecond` and `tempo`), so fast songs snap and slow
/// ones take their time. The scene settles well before the line ends and holds
/// still; it leaves when the line changes. Untimed lyrics move at a medium pace.
struct LyricChoreography: Equatable, Sendable {
    /// The entrance runs from 0 to here; the one action follows for `action` seconds.
    var entrance: Double
    var action: Double
    /// How long the exit takes once the line changes.
    var exit: Double
    /// How much faster than its resting pace the scene moves (0.75…1.35, Mood's tempo).
    var tempo: Double

    /// When the scene is still: Reduce Motion and still previews show this pose.
    var settled: Double { entrance + action }

    static func timing(span: ClosedRange<TimeInterval>?, words: Int) -> LyricChoreography {
        let tempo = MoodTreatment.tempo(wordsPerSecond: MoodTreatment.wordsPerSecond(words: words, span: span))
        // How long the line shows: its sung span (it appears `LyricTimeline.lead` early,
        // and so does the next, so the same length), or a medium guess when untimed.
        let length = span.map { max(0.5, $0.upperBound - $0.lowerBound) }
            ?? max(3.5, Double(max(words, 1)) / MoodTreatment.mediumPace)
        var entrance = 0.6 / tempo
        var action = 1.3 / tempo
        // Settle by 70% of the line, so the scene holds while the line finishes; very
        // short lines squeeze both, never below a readable floor.
        let budget = length * 0.7
        if entrance + action > budget {
            let squeeze = budget / (entrance + action)
            entrance = max(0.25, entrance * squeeze)
            action = max(0.4, action * squeeze)
        }
        return LyricChoreography(entrance: entrance, action: action, exit: min(0.7, max(0.3, 0.5 / tempo)), tempo: tempo)
    }

    /// Seconds into the line for a beat: 0…1 is the entrance, 1…2 the action.
    func seconds(atBeat beat: Double) -> Double {
        beat <= 1 ? max(0, beat) * entrance : entrance + min(1, beat - 1) * action
    }
}
