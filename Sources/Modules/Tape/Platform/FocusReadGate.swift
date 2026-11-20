// Accessed under AXWindowServer's registry lock. Reads never supersede keyboard commands.
struct FocusReadTicket {
    let report: UInt64
    let command: Int
}

struct FocusReadGate {
    private var latest: UInt64 = 0
    mutating func request(command: Int) -> FocusReadTicket {
        latest &+= 1
        return FocusReadTicket(report: latest, command: command)
    }
    func accepts(_ ticket: FocusReadTicket, command: Int) -> Bool {
        ticket.report == latest && ticket.command == command
    }
}
