import Foundation

struct FrameWrite {
    let id: WindowID
    let frame: CGRect
    let generation: Int
    let restoring: Bool
    init(id: WindowID, frame: CGRect, generation: Int, restoring: Bool = false) {
        self.id = id; self.frame = frame; self.generation = generation; self.restoring = restoring
    }
}

/// One serial lane per app, with only the newest waiting frame for each window.
/// Updating a pending window retains its place, so a busy window cannot starve its peers.
final class FrameWriteQueue {
    private let lock = NSLock()
    private var pending: [Int32: [WindowID: FrameWrite]] = [:]
    private var order: [Int32: [WindowID]] = [:]
    private var workers: [Int32: DispatchQueue] = [:]
    private var scheduled: Set<Int32> = []
    private var idleCallbacks: [() -> Void] = []
    private let write: (FrameWrite) -> Void

    init(write: @escaping (FrameWrite) -> Void) { self.write = write }

    func enqueue(_ jobs: [(Int32, FrameWrite)]) {
        lock.lock()
        var starts: [(Int32, DispatchQueue)] = []
        for (pid, job) in jobs {
            if pending[pid]?[job.id] == nil { order[pid, default: []].append(job.id) }
            pending[pid, default: [:]][job.id] = job
            if scheduled.insert(pid).inserted {
                let worker = workers[pid] ?? DispatchQueue(label: "dev.opensource.MacSpaces.tape.frames.\(pid)", qos: .userInteractive)
                workers[pid] = worker
                starts.append((pid, worker))
            }
        }
        lock.unlock()
        for (pid, worker) in starts { worker.async { [self] in drain(pid) } }
    }

    private func drain(_ pid: Int32) {
        while true {
            lock.lock()
            guard let id = order[pid]?.first, let job = pending[pid]?.removeValue(forKey: id) else {
                scheduled.remove(pid)
                pending.removeValue(forKey: pid)
                order.removeValue(forKey: pid)
                workers.removeValue(forKey: pid)
                let callbacks = scheduled.isEmpty ? idleCallbacks : []
                if scheduled.isEmpty { idleCallbacks.removeAll() }
                lock.unlock()
                callbacks.forEach { $0() }
                return
            }
            order[pid]?.removeFirst()
            lock.unlock()
            write(job)
        }
    }

    func whenIdle(_ completion: @escaping () -> Void) {
        lock.lock()
        if scheduled.isEmpty { lock.unlock(); completion() }
        else { idleCallbacks.append(completion); lock.unlock() }
    }

    func cancelPending() {
        lock.lock(); pending.removeAll(); order.removeAll(); lock.unlock()
    }
}
