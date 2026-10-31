import Foundation

/// The Fluent Emoji catalog the Scenes lyric style matches against
/// (`Sources/Resources/sticker-index.json`, from `Scripts/build-sticker-index.py`):
/// each emoji's name, group, keywords and the paths of its 3D still and, when
/// Microsoft made one, its animation. Decoded once; the word tables are built here
/// so matching is only lookups. Pure, so `check-lyrics` reads the real file.
struct StickerIndex: Sendable {
    struct Emoji: Sendable {
        let name: String
        let group: String
        let still: String
        let animated: String?
        /// People and faces are drawn only for words that name them outright.
        var isFigure: Bool { group == "People & Body" || group == "Smileys & Emotion" }
    }

    private struct File: Decodable {
        struct Entry: Decodable { let n: String; let g: String; let k: [String]; let s: String; let a: String? }
        let still: String
        let animated: String
        let emoji: [Entry]
    }

    let stillBase: String
    let animatedBase: String
    let emoji: [Emoji]
    private let byName: [String: Int]
    /// Word → the emoji whose whole name is that word ("rose", "mirrorball").
    let exact: [String: Int]
    /// Word → emoji named for it: the last word before any "with", "of", "on"…
    /// ("alarm clock" → clock, "cloud with rain" → cloud).
    let heads: [String: [Int]]
    /// Word → emoji that show it after a preposition ("glass of milk" → milk).
    /// Objects and nature only.
    let details: [String: [Int]]
    /// Word → emoji listing it among Microsoft's keywords. Objects and nature only.
    let keywords: [String: [Int]]
    /// "two words" → the emoji with that two-word name ("shooting star").
    let phrases: [String: Int]
    /// Each emoji's name words, for telling apart emoji that share a head.
    let nameWords: [[String]]

    static let prepositions: Set<String> = ["with", "of", "on", "in", "from", "without", "at", "over", "behind", "and"]

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        stillBase = file.still
        animatedBase = file.animated
        emoji = file.emoji.map { Emoji(name: $0.n, group: $0.g, still: $0.s, animated: $0.a) }
        var byName: [String: Int] = [:], exact: [String: Int] = [:], heads: [String: [Int]] = [:]
        var details: [String: [Int]] = [:], keywords: [String: [Int]] = [:], phrases: [String: Int] = [:]
        var nameWords: [[String]] = []
        for (index, entry) in file.emoji.enumerated() {
            let item = emoji[index]
            byName[entry.n] = index
            let words = StickerMatch.words(entry.n)
            nameWords.append(words)
            guard !words.isEmpty else { continue }
            exact[words.joined()] = index
            if words.count == 2 { phrases[words.joined(separator: " ")] = index }
            let cut = words.firstIndex(where: Self.prepositions.contains) ?? words.count
            if cut > 0 {
                let head = words[cut - 1]
                // "Person running", "Woman dancing": a figure doing something common.
                if !(item.isFigure && head.hasSuffix("ing")) { heads[head, default: []].append(index) }
            }
            guard !item.isFigure else { continue }
            for word in words[min(cut + 1, words.count)...] where !Self.prepositions.contains(word) && !word.hasSuffix("ing") {
                details[word, default: []].append(index)
            }
            for word in entry.k { keywords[word, default: []].append(index) }
        }
        self.byName = byName; self.exact = exact; self.heads = heads
        self.details = details; self.keywords = keywords; self.phrases = phrases; self.nameWords = nameWords
    }

    func named(_ name: String) -> Emoji? { byName[name].map { emoji[$0] } }
    func contains(_ name: String) -> Bool { byName[name] != nil }

    /// Only Microsoft's GitHub-hosted files, over https; spaces in paths are encoded.
    func stillURL(_ item: Emoji) -> URL? { Self.url(stillBase, item.still) }
    func animatedURL(_ item: Emoji) -> URL? { item.animated.flatMap { Self.url(animatedBase, $0) } }

    static let hosts: Set<String> = ["raw.githubusercontent.com", "media.githubusercontent.com"]

    private static func url(_ base: String, _ path: String) -> URL? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + encoded), url.scheme == "https", let host = url.host, hosts.contains(host) else { return nil }
        return url
    }
}

/// Picks the one Fluent Emoji a lyric line is clearly about, or none: better none
/// than wrong. Curated subjects (`LyricSubject`, with its slang and context rules)
/// come first and keep their own pictures; any other concrete word can draw the
/// emoji named for it. Pure, so `check-lyrics` covers it.
enum StickerMatch {
    /// The picture for each curated subject; these ship in the app (`scene-<subject>`).
    static let subjectEmoji: [LyricSubject: String] = [
        .money: "Money with wings", .cards: "Joker", .crowd: "Raising hands", .dance: "Mirror ball", .heart: "Red heart",
        .heartbreak: "Broken heart", .rose: "Rose", .fire: "Fire", .rain: "Cloud with rain", .sun: "Sun",
        .moon: "Crescent moon", .stars: "Glowing star", .drive: "Automobile", .phone: "Mobile phone", .ocean: "Water wave",
        .city: "Cityscape", .crown: "Crown", .diamond: "Gem stone", .drink: "Wine glass", .smoke: "Fog",
        .time: "Alarm clock", .plane: "Airplane", .home: "House", .tears: "Crying face", .music: "Musical notes",
        .snow: "Snowflake", .eyes: "Eyes", .cup: "Cup with straw", .sneakers: "Running shoe", .guitar: "Guitar",
        .microphone: "Microphone",
    ]

    /// The curated subject whose bundled picture is this emoji.
    static let bundledSubject: [String: LyricSubject] = Dictionary(uniqueKeysWithValues: subjectEmoji.map { ($1, $0) })

    /// A sharper picture within a curated subject when the line names it: champagne
    /// is a popping bottle, not a wine glass; a sunset is a sunset.
    static let refinements: [LyricSubject: [String: String]] = [
        .money: ["coin": "Coin", "coins": "Coin", "dollar": "Dollar banknote", "dollars": "Dollar banknote",
                 "rich": "Money bag", "riches": "Money bag", "fortune": "Money bag", "millionaire": "Money bag",
                 "billionaire": "Money bag", "bag": "Money bag", "wallet": "Money bag"],
        .cards: ["dice": "Game die", "casino": "Slot machine", "jackpot": "Slot machine"],
        .rose: ["flowers": "Bouquet", "bouquet": "Bouquet", "tulips": "Tulip", "daisy": "Blossom", "daisies": "Blossom",
                "blossom": "Blossom", "blooming": "Cherry blossom"],
        .rain: ["umbrella": "Umbrella with rain drops", "storm": "Cloud with lightning and rain",
                "storms": "Cloud with lightning and rain", "stormy": "Cloud with lightning and rain",
                "thunder": "Cloud with lightning and rain"],
        .sun: ["sunrise": "Sunrise", "sunset": "Sunset", "summer": "Beach with umbrella"],
        .moon: ["full moon": "Full moon", "new moon": "New moon"],
        .stars: ["galaxy": "Milky way", "constellation": "Milky way", "constellations": "Milky way", "comet": "Comet",
                 "shooting star": "Shooting star", "shooting stars": "Shooting star"],
        .drive: ["fire truck": "Fire engine", "motorcycle": "Motorcycle", "truck": "Pickup truck"],
        .phone: ["telephone": "Telephone", "hotline": "Telephone", "dial": "Telephone"],
        .ocean: ["beach": "Beach with umbrella"],
        .city: ["skyline": "Cityscape at dusk", "neon": "Cityscape at dusk"],
        .drink: ["champagne": "Bottle with popping cork", "bottle": "Bottle with popping cork", "beer": "Beer mug",
                 "cheers": "Clinking glasses", "cocktail": "Cocktail glass", "cocktails": "Cocktail glass",
                 "whiskey": "Tumbler glass", "whisky": "Tumbler glass", "bourbon": "Tumbler glass", "liquor": "Tumbler glass"],
        .smoke: ["cigarette": "Cigarette", "cigarettes": "Cigarette"],
        .time: ["hourglass": "Hourglass not done"],
        .tears: ["sobbing": "Loudly crying face", "weeping": "Loudly crying face"],
        .music: ["radio": "Radio", "speakers": "Speaker high volume", "stereo": "Speaker high volume"],
        .snow: ["snowman": "Snowman"],
        .eyes: ["blink": "Eye"],
        .crowd: ["cheering": "Clapping hands"],
        .heart: ["valentine": "Heart with ribbon"],
    ]

    /// Words whose own emoji is ambiguous or off, with the picture to draw instead;
    /// an empty name draws nothing.
    static let preferred: [String: String] = [
        "tree": "Deciduous tree", "trees": "Deciduous tree", "cake": "Birthday cake", "tea": "Teacup without handle",
        "rice": "Cooked rice", "book": "Open book", "books": "Books", "shoe": "Mans shoe", "shoes": "Mans shoe",
        "boots": "Womans boot", "heels": "High-heeled shoe", "kiss": "Kiss mark", "kisses": "Kiss mark",
        "lips": "Kiss mark", "lipstick": "Lipstick", "devil": "Smiling face with horns", "clown": "Clown face",
        "santa": "Santa claus", "police": "Police car light", "siren": "Police car light", "coffee": "Hot beverage",
        "planet": "Ringed planet", "globe": "Globe showing americas", "speaker": "Speaker high volume",
        "letter": "Love letter", "ring": "Ring", "headphones": "Headphone", "camera": "Camera", "taxi": "Taxi",
        "bike": "Bicycle", "candles": "Candle", "ghosts": "Ghost", "angel": "Baby angel", "angels": "Baby angel",
        "rocket": "Rocket", "island": "Desert island", "ticket": "Ticket", "tickets": "Admission tickets",
        "piano": "Musical keyboard", "unicorn": "Unicorn", "dragon": "Dragon", "butterflies": "Butterfly",
        "blood": "Drop of blood", "pumpkin": "Jack-o-lantern", "bubbles": "Bubbles", "lamp": "Couch and lamp",
        "lip": "Kiss mark", "mail": "Envelope", "skeleton": "Skull", "skeletons": "Skull", "lightning": "High voltage",
        "apple": "Red apple", "apples": "Red apple", "milk": "Glass of milk", "medal": "1st place medal",
        "hat": "Top hat", "seashell": "Spiral shell", "seashells": "Spiral shell", "chocolate": "Chocolate bar",
        "movie": "Clapper board", "movies": "Clapper board", "teeth": "Tooth", "witch": "Person mage",
        "cowboy": "Cowboy hat face", "doctor": "Health worker", "nurse": "Health worker", "hearts": "",
    ]

    /// Microsoft's keywords include moods and loose associations ("proud" is a peacock,
    /// "idea" a light bulb, "freedom" a broken chain), so a keyword alone draws its emoji
    /// only for these words, each another name for the thing ("burger", "raven", "ufo").
    static let synonyms: Set<String> = [
        "birthday", "burger", "christmas", "halloween", "soccer", "golf", "chess", "circus", "confetti", "credit",
        "crow", "raven", "donut", "sausage", "hurricane", "typhoon", "twister", "whirlwind", "pasta", "noodle", "ramen",
        "steak", "subway", "sax", "squirrel", "tortoise", "terrapin", "ufo", "yacht", "eyeglasses", "grape", "peanut",
        "pancake", "blueberry", "bee", "bull", "hippo", "alpaca", "ape", "mule", "burro", "racehorse", "cemetery",
        "graveyard", "tombstone", "grave", "funeral", "dynamite", "torch", "maple", "sandals", "slipper", "sleigh",
        "ski", "skydive", "scuba", "snorkeling", "theater", "theatre", "tokyo", "saturn", "tyrannosaurus",
        "brontosaurus", "phoenix", "wizard", "teddy", "plush", "jigsaw", "puzzle", "rugby", "hoop", "puck", "judo",
        "karate", "taekwondo", "billiard", "dart", "makeup", "cosmetics", "shampoo", "sunscreen", "lotion", "earbud",
        "stew", "curry", "soda", "cereal", "tempura", "prawn", "shellfish", "ladybug", "ladybird", "grasshopper",
        "roach", "maggot", "earthworm", "euro", "vhs", "fax", "floppy", "controller", "jacket", "trousers",
        "stocking", "graduation", "haircut", "barber", "carousel", "ferris", "playground", "picnic", "hiking",
        "eruption", "reef", "kiwi", "aubergine", "maize", "pickle", "kale", "baguette", "loaf", "naan", "pita",
        "empanada", "pierogi", "dumpling", "pudding", "pickup", "soldier", "army", "boxing", "frankfurter",
    ]

    /// Words that never draw an emoji of their own. Function words, pronouns and filler;
    /// the everyday verbs, people and abstractions lyrics are made of ("life", "world",
    /// "way", "day", "mind", "baby", "girl"); colours, numbers and adjectives that name
    /// part of an emoji, not the thing ("red", "top", "hot", "full"); words whose
    /// emoji is another sense than the lyric's ("watch me", "bear with me", "no cap",
    /// "roll with it", "lost track", "palm of my hand", "leaves" as in goes); slang
    /// for guns and drugs, which emoji would picture wrong or make light of; and crude
    /// words. Words a curated subject lists (`LyricSubject.listed`: love, night,
    /// time, light, gold, cold…) are left to it.
    static let stopWords: Set<String> = [
        // Function words, pronouns, filler.
        "the", "and", "but", "for", "nor", "yet", "you", "your", "yours", "youre", "its", "his", "her", "hers", "him",
        "she", "they", "them", "their", "theirs", "our", "ours", "who", "whom", "whose", "why", "how", "which", "these",
        "those", "here", "onto", "upon", "under", "above", "below", "across", "after", "before", "again", "around",
        "away", "down", "off", "out", "all", "any", "each", "both", "most", "many", "few", "less", "such", "also", "too",
        "very", "now", "once", "ever", "maybe", "are", "was", "has", "had", "having", "does", "did", "done", "doing",
        "shall", "may", "might", "must", "can", "cant", "dont", "wont", "aint", "isnt", "wasnt", "didnt", "doesnt",
        "couldnt", "wouldnt", "shouldnt", "ive", "ill", "youll", "youve", "youd", "theyre", "thats", "whats", "lets",
        "tryna", "cuz", "till", "until", "while", "although", "yea", "yes", "nah", "hey", "ooh", "oooh", "ohh", "aah",
        "whoa", "woah", "mmm", "hmm", "uhh", "doo", "lala", "nana", "hoo", "huh", "okay", "alright", "please",
        "not", "one", "ones", "own", "else", "yall", "ima", "imma", "gon", "aye",
        // People and address.
        "babe", "boo", "honey", "darling", "darlin", "sugar", "sweetheart", "lady", "ladies", "guy", "guys", "dude",
        "bro", "brother", "sister", "mama", "mother", "father", "daddy", "papa", "son", "daughter", "child", "children",
        "kid", "kids", "homie", "homies", "friend", "friends", "lover", "person", "family", "nobody", "somebody",
        "anybody", "anyone", "stuff", "self", "myself", "yourself", "baby", "babies",
        // Everyday verbs.
        "feel", "feels", "felt", "knew", "known", "knowing", "wanted", "need", "needed", "needs", "come", "comes",
        "coming", "came", "get", "gets", "got", "gotten", "getting", "make", "makes", "made", "making", "take",
        "takes", "took", "taken", "taking", "give", "gives", "gave", "given", "giving", "say", "says", "said",
        "saying", "tell", "told", "telling", "think", "thought", "thinking", "let", "keep", "kept", "put", "seen",
        "saw", "hold", "holding", "held", "run", "runs", "ran", "running", "fall", "falls", "fell", "falling",
        "fallen", "stay", "leave", "leaves", "left", "leaving", "lose", "lost", "losing", "find", "found", "try",
        "tried", "trying", "turn", "turned", "show", "work", "play", "playing", "played", "live", "living", "lived",
        "die", "dying", "died", "wait", "waiting", "walk", "walking", "talk", "talking", "stand", "sit", "break",
        "broke", "hit", "bring", "hear", "heard", "believe", "remember", "forget", "change", "start", "stop", "end",
        "open", "close", "wake", "goes", "going", "gone", "went", "watch", "bear", "roll", "rolling", "rock", "rocks",
        "rocking", "drop", "drops", "pop", "popping", "slide", "tie", "bow", "date", "spin", "swing", "jump",
        "shoot", "shot", "blow", "blowing", "smile", "smiling", "laugh", "laughing", "kill", "killing", "save",
        "fight", "fighting", "hurt", "hurts", "pray", "praying", "touch", "kick", "push", "pull", "throw", "catch",
        "sleep", "sleeping", "dream", "dreams", "dreaming", "wish", "hope", "lie", "lies", "lying", "cross",
        "sign", "mark", "point", "check", "fit", "pick", "lead", "count",
        // Abstractions, body and places that are everywhere in lyrics.
        "life", "world", "way", "ways", "day", "days", "today", "tomorrow", "yesterday", "year", "years", "week",
        "moment", "place", "side", "part", "piece", "line", "lines", "game", "games", "story", "word", "words", "name",
        "soul", "spirit", "head", "face", "faces", "hand", "arm", "arms", "body", "finger", "fingers", "fist", "thumb",
        "foot", "feet", "hair", "nail", "nails", "back", "front", "top", "bottom", "edge", "inside", "outside", "truth",
        "pain", "room", "ground", "air", "space", "earth", "heaven", "hell", "god", "lord", "jesus", "note", "notes",
        "track", "tracks", "present", "kind", "sort", "type", "case", "suit", "suits", "lot", "lots", "spot", "shade",
        "cap", "caps", "palm", "palms", "spring", "video", "picture", "pictures", "sound", "voice", "noise", "mood",
        "vibe", "vibes", "feeling", "feelings", "power", "control", "peace", "war", "fun", "party", "level", "number",
        "problem", "problems", "reason", "chance", "rest", "safe", "bank", "news", "trouble", "magic",
        // Names whose emoji is another sense than the lyric's usual one: "let my guard
        // down", "off the hook", "don't judge me", "record label", "seal the deal", a
        // fan, a red flag, "cut me deep", "on board", "the last straw", "rays of sun".
        "guard", "hook", "judge", "label", "link", "mate", "scroll", "seal", "bags", "board", "bolt", "bust", "busts",
        "cane", "ceremony", "cover", "cracker", "curl", "cut", "decorative", "decreasing", "dish", "fan", "fans", "flag",
        "flash", "frames", "fruit", "gesture", "handle", "horizontally", "vertically", "horn", "large", "mask", "net",
        "pan", "park", "parked", "pile", "pin", "points", "pump", "rail", "ray", "rays", "root", "roots", "salute",
        "scale", "score", "slash", "slider", "springs", "straw", "streamer", "struck", "swirl", "symbol", "tabs",
        "tube", "uniform", "yen", "exclamation", "index", "dividers", "knobs", "chart", "page", "plant", "needle",
        // Colours, numbers and adjectives.
        "good", "bad", "best", "better", "worse", "worst", "big", "small", "long", "short", "high", "low", "new",
        "old", "young", "real", "true", "free", "right", "wrong", "last", "first", "next", "same", "other", "whole",
        "sweet", "pretty", "beautiful", "crazy", "wild", "hard", "easy", "fast", "slow", "deep", "early", "alone",
        "together", "lonely", "happy", "angry", "mad", "sick", "tired", "full", "empty", "broken", "red", "black",
        "white", "blue", "green", "yellow", "orange", "pink", "brown", "silver", "heavy", "warm", "cool", "fresh",
        "clean", "dirty", "nice", "fine", "sure", "ready", "double", "single", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten", "hundred", "thousand", "twenty", "thirty", "forty", "fifty", "half",
        "second", "third", "loud", "quiet", "strong", "weak", "dead", "alive", "flying", "shooting",
        // Guns, drugs and their slang; crude words.
        "gun", "guns", "pistol", "glock", "strap", "choppa", "chopper", "stick", "pole", "iron", "tool", "tools",
        "bullet", "bullets", "coke", "crack", "molly", "dope", "plug", "trap", "brick", "bricks", "paper", "beef",
        "pack", "pot", "gas", "zaza", "pills", "powder", "bars", "stone", "stones", "stoned", "shit", "fuck",
        "fucking", "fuckin", "damn", "goddamn", "ass", "dick", "cock", "pussy", "balls", "nuts", "nut", "booty",
        "cum", "tits", "bitch", "bitches", "hoe", "hoes", "nigga", "niggas", "poop", "glizzy",
    ]

    /// Sayings whose words aren't the things they name: their words draw nothing.
    static let idioms: [String] = [
        "cold turkey", "break a leg", "kick the bucket", "basket case", "bad blood", "hat trick", "piece of cake",
        "cat got your tongue", "under the weather", "spill the beans", "in a nutshell", "red flag", "black sheep",
    ]

    /// Lower-case words with apostrophes dropped, as `LyricSubject.words`.
    static func words(_ text: String) -> [String] { LyricSubject.words(text) }

    /// The word, then simple plurals and possessives undone: roses → rose,
    /// cherries → cherry, boxes → box, money's → money.
    static func stems(_ word: String) -> [String] {
        var result = [word]
        if word.hasSuffix("ies"), word.count > 4 { result.append(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("es"), word.count > 4 { result.append(String(word.dropLast(2))) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), word.count > 3 { result.append(String(word.dropLast())) }
        // "octopus's" reads as "octopuss" once the apostrophe goes.
        if word.hasSuffix("ss"), word.count > 4 { result.append(String(word.dropLast())) }
        return result
    }

    /// How surely a word names an emoji: its whole name beats the word it's named for,
    /// which beats a detail of its name, which beats one of Microsoft's keywords.
    enum Tier: Int, Comparable {
        case keyword = 2, detail = 4, head = 7, exact = 10, preferred = 11, phrase = 12
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct Candidate: Equatable {
        let emoji: String
        let tier: Tier
        let word: String
    }

    /// The emoji a single line word names, if it names one clearly. `line` is the
    /// whole line's words, which can tell apart emoji that share a head ("palm tree").
    static func candidate(_ word: String, line: Set<String>, in index: StickerIndex) -> Candidate? {
        guard word.count >= 3 else { return nil }
        var best: (Int, Tier, String)?
        for (step, form) in stems(word).enumerated() {
            guard !stopWords.contains(form), !LyricSubject.listed(form), !LyricSubject.stopWords.contains(form) else {
                if step == 0 { return nil } else { continue }
            }
            if let name = preferred[form] {
                guard !name.isEmpty, index.contains(name) else { return nil }
                // The line can still name a sharper one: "christmas tree", "green apple".
                let named = (index.heads[form]?.count ?? 0) > 1 ? distinct(index.heads[form], form, line: line, in: index) : nil
                return Candidate(emoji: named.map { index.emoji[$0].name } ?? name, tier: .preferred, word: word)
            }
            func consider(_ found: Int?, _ tier: Tier) {
                guard let found, best == nil || tier > best!.1 else { return }
                best = (found, tier, form)
            }
            consider(index.exact[form], .exact)
            consider(distinct(index.heads[form], form, line: line, in: index), .head)
            if let details = index.details[form], details.count == 1 { consider(details[0], .detail) }
            // A keyword counts only when it's another name for the thing and belongs
            // to one emoji: "raven" is the blackbird, but "animal" could be anything.
            if synonyms.contains(form), let tagged = index.keywords[form], tagged.count == 1 { consider(tagged[0], .keyword) }
        }
        // A plural name: "cherry" is the cherries, "grape" the grapes.
        if best == nil, !stopWords.contains(word), !LyricSubject.listed(word) {
            let plurals = [word + "s", word + "es"] + (word.hasSuffix("y") ? [String(word.dropLast()) + "ies"] : [])
            for plural in plurals { if let found = index.exact[plural] { best = (found, .exact, plural); break } }
        }
        return best.map { Candidate(emoji: index.emoji[$0.0].name, tier: $0.1, word: word) }
    }

    /// One emoji for a head several share only when the line's other words pick it out
    /// ("palm tree", "world map"), or when the others are the same figure as a man and
    /// a woman ("vampire" is the person vampire); otherwise none.
    private static func distinct(_ found: [Int]?, _ head: String, line: Set<String>, in index: StickerIndex) -> Int? {
        guard let found, !found.isEmpty else { return nil }
        if found.count == 1 { return found[0] }
        let named = found.filter { candidate in
            index.nameWords[candidate].contains { $0 != head && !StickerIndex.prepositions.contains($0) && line.contains($0) }
        }
        if named.count == 1 { return named[0] }
        let neutral = found.filter { !index.emoji[$0].name.hasPrefix("Man ") && !index.emoji[$0].name.hasPrefix("Woman ") }
        return neutral.count == 1 && index.emoji[neutral[0]].isFigure ? neutral[0] : nil
    }

    /// The emoji the line is clearly about, or nil. Ranking: a two-word emoji name
    /// sung as a phrase ("shooting star", "ice cream") 12; a curated subject 11, or 14
    /// when the poster's headline names it; then each other word by how surely it names
    /// an emoji (`Tier`), plus 3 when it's the headline, 1 for an object, food, animal,
    /// place or activity over a face or figure, and a half for an animated emoji. Ties
    /// go to the phrase, then the curated subject, then the earlier word.
    static func pick(_ line: String, hero: String, in index: StickerIndex) -> String? {
        let ordered = words(Lyrics.asides(line).sung)
        guard !ordered.isEmpty else { return nil }
        let headline = words(hero).first ?? ""
        let present = Set(ordered)
        let joined = " \(ordered.joined(separator: " ")) "
        let sayings = Set(idioms.filter { joined.contains(" \($0) ") }.flatMap { words($0) })
        var best: (emoji: String, score: Double)?
        func offer(_ emoji: String, _ score: Double) {
            if best == nil || score > best!.score { best = (emoji, score) }
        }
        // Two-word names sung together.
        for (position, word) in ordered.enumerated().dropLast() {
            let next = ordered[position + 1]
            guard !sayings.contains(word), !sayings.contains(next) else { continue }
            for second in stems(next) {
                guard let found = index.phrases["\(word) \(second)"] else { continue }
                // "Old man", "smiling face": a figure named by two common words.
                guard !(index.emoji[found].isFigure && stopWords.contains(word) && stopWords.contains(second)) else { break }
                offer(index.emoji[found].name, Double(Tier.phrase.rawValue) + (word == headline || next == headline ? 3 : 0))
                break
            }
        }
        if let subject = LyricSubject.vote(line, hero: hero) {
            let named = names(subject, headline)
            offer(refined(subject, ordered, headline: headline, in: index), Double(Tier.preferred.rawValue) + (named ? 3 : 0))
        }
        var seen = Set<String>()
        for word in ordered where !sayings.contains(word) && seen.insert(word).inserted {
            guard let found = candidate(word, line: present, in: index), let item = index.named(found.emoji) else { continue }
            var score = Double(found.tier.rawValue)
            if word == headline { score += 3 }
            if !item.isFigure { score += 1 }
            if item.animated != nil { score += 0.5 }
            offer(found.emoji, score)
        }
        return best?.emoji
    }

    /// Whether the headline is one of the subject's own words.
    private static func names(_ subject: LyricSubject, _ headline: String) -> Bool {
        let lists = [LyricSubject.strong[subject], LyricSubject.weak[subject], LyricSubject.contextual[subject]]
        return lists.contains { $0?.contains(headline) == true }
            || subject == .heartbreak && (headline == "heart" || LyricSubject.breaking.contains(headline))
    }

    /// The subject's picture, sharpened by a word the line names (headline first).
    static func refined(_ subject: LyricSubject, _ ordered: [String], headline: String, in index: StickerIndex) -> String {
        let fallback = subjectEmoji[subject]!
        guard let table = refinements[subject] else { return fallback }
        let pairs = zip(ordered, ordered.dropFirst()).map { "\($0) \($1)" }
        for key in pairs + [headline] + ordered {
            if let name = table[key], index.contains(name) { return name }
        }
        return fallback
    }

    /// Every emoji name the tables mention, for the check that each exists.
    static var mentioned: [String] {
        Array(subjectEmoji.values) + refinements.values.flatMap(\.values) + preferred.values.filter { !$0.isEmpty }
    }
}
