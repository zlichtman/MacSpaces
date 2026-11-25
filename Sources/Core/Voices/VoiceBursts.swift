import Foundation

/// Siren's short bursts: someone who only ever speaks briefly leaves no clip long enough to carry
/// their voice, so when none of a person's clips reaches `longEnough`, their clips are joined, in
/// the order they were said, into clips of up to `joinedLimit` with `pause` of quiet between pieces.
/// Clips from different recordings aren't joined (the rooms and microphones differ). Pure, so
/// `Scripts/check-voices.sh` checks it; the helper joins the audio.
enum VoiceBursts {
    /// A clip this long carries a voice on its own (Siren's 8 s).
    static let longEnough = 8.0
    /// A joined clip holds up to this much, pauses included (Siren's 15 s; the engines take 20).
    static let joinedLimit = 15.0
    /// Quiet between joined pieces (Siren's quarter second).
    static let pause = 0.25

    /// One of a person's clips: the recording it was cut from, where it starts there, its length.
    struct Piece: Equatable, Sendable {
        let recording: Int
        let start: Double
        let seconds: Double
    }

    /// Whether `pieces` should be joined: more than one, and none long enough on its own.
    static func needsJoining(_ pieces: [Piece]) -> Bool {
        pieces.count > 1 && (pieces.map(\.seconds).max() ?? 0) < longEnough
    }

    /// The clips to join, as indices into `pieces`: each recording's in the order they were said,
    /// a new clip once the next piece (and its pause) would pass `joinedLimit`. A group of one is
    /// that clip as it was. Everything, ungrouped, when they don't need joining.
    static func groups(_ pieces: [Piece]) -> [[Int]] {
        guard needsJoining(pieces) else { return pieces.indices.map { [$0] } }
        let order = pieces.indices.sorted {
            (pieces[$0].recording, pieces[$0].start) < (pieces[$1].recording, pieces[$1].start)
        }
        var groups: [[Int]] = []
        var length = 0.0
        for index in order {
            let piece = pieces[index]
            if let last = groups.last?.last, pieces[last].recording == piece.recording,
               length + pause + piece.seconds <= joinedLimit {
                groups[groups.count - 1].append(index)
                length += pause + piece.seconds
            } else {
                groups.append([index])
                length = piece.seconds
            }
        }
        return groups
    }

    /// A joined clip's length: its pieces with a pause between each.
    static func seconds(_ pieces: [Piece], group: [Int]) -> Double {
        group.reduce(0) { $0 + pieces[$1].seconds } + pause * Double(max(0, group.count - 1))
    }

    /// `values` averaged by each piece's length (the joined clip's loudness and liveliness).
    static func weighted(_ values: [(value: Double, seconds: Double)]) -> Double {
        let total = values.reduce(0) { $0 + max(0, $1.seconds) }
        guard total > 0 else { return values.first?.value ?? 0 }
        return values.reduce(0) { $0 + $1.value * max(0, $1.seconds) } / total
    }
}
