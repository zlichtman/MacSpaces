import Foundation

#if DEBUG
import Darwin
@preconcurrency import MLX
import os

/// Debug builds only: where a speak request's memory goes, for `Scripts/compare-siren.sh`. The
/// harness asks for it by leaving an empty helper-memory.txt beside the request's output; each
/// mark then appends MLX's peak since the last mark (what speech held at its highest), what it
/// holds now and keeps in its buffer cache, and the helper's footprint and lifetime peak.
enum MemoryTrace {
    private static let file = OSAllocatedUnfairLock<URL?>(initialState: nil)

    static func begin(output: URL) {
        let trace = output.deletingLastPathComponent().appendingPathComponent("helper-memory.txt")
        file.withLock { $0 = FileManager.default.fileExists(atPath: trace.path) ? trace : nil }
        mark("start " + output.lastPathComponent)
    }

    static func mark(_ what: @autoclosure () -> String) {
        guard let trace = file.withLock({ $0 }), let handle = try? FileHandle(forWritingTo: trace) else { return }
        defer { try? handle.close() }
        let peak = Memory.peakMemory
        Memory.peakMemory = 0
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        func mb<T: BinaryInteger>(_ bytes: T) -> Int { Int(bytes) / 1_048_576 }
        let line = String(format: "%-34@ mlx peak %5d active %5d cache %4d MB | footprint %5d lifetime max %5d MB\n",
                          what() as NSString, mb(peak), mb(Memory.activeMemory), mb(Memory.cacheMemory),
                          status == 0 ? mb(info.ri_phys_footprint) : -1, status == 0 ? mb(info.ri_lifetime_max_phys_footprint) : -1)
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
    }
}
#else
/// Release builds trace nothing (see the Debug definition).
enum MemoryTrace {
    @inline(__always) static func begin(output: URL) {}
    @inline(__always) static func mark(_ what: @autoclosure () -> String) {}
}
#endif
