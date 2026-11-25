import Foundation

@main struct SpacesChecks {
    static func space(_ uuid: String, type: Int = 0) -> [String: Any] {
        ["uuid": uuid, "type": type, "ManagedSpaceID": 4, "id64": 4]
    }

    static func display(_ identifier: String, current: String, _ spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": space(current), "Spaces": spaces]
    }

    static func main() {
        parsing()
        badShapes()
        finding()
        changing()
        words()
        shortcuts()
        jumping()
        print("Spaces checks passed: desktops per display in order, full-screen spaces unnumbered, unexpected shapes hide the feature, shared Spaces, what counts as a change, labels and names, reading shortcuts, planning a jump")
    }

    static func parsing() {
        let raw: [[String: Any]] = [
            display("A", current: "two", [space("one"), space("full", type: 4), space("two"), space("three")]),
            display("B", current: "b-one", [space("b-one")]),
        ]
        let displays = SpaceLayout.parse(raw)!
        precondition(displays.count == 2 && displays[0].identifier == "A")
        precondition(displays[0].desktops.map(\.uuid) == ["one", "two", "three"], "Full screen isn't a desktop")
        precondition(displays[0].desktops.map(\.number) == [1, 2, 3], "Numbers skip the full-screen space")
        precondition(displays[0].current == SpaceDesktop(uuid: "two", number: 2))
        precondition(displays[1].current?.number == 1, "Each display numbers its own")
        // On a full-screen space there's no current desktop.
        let full = SpaceLayout.parse([display("A", current: "full", [space("one"), space("full", type: 4)])])!
        precondition(full[0].current == nil && full[0].desktops.count == 1)
        // Fields the app doesn't read don't matter.
        var extra = display("A", current: "one", [space("one")])
        extra["Collapsed Space"] = "anything"
        precondition(SpaceLayout.parse([extra]) != nil)
    }

    static func badShapes() {
        precondition(SpaceLayout.parse(nil) == nil)
        precondition(SpaceLayout.parse("nonsense") == nil)
        precondition(SpaceLayout.parse([[String: Any]]()) == nil, "An empty list says nothing")
        precondition(SpaceLayout.parse([["Spaces": []]]) == nil, "No identifier")
        precondition(SpaceLayout.parse([["Display Identifier": "A", "Current Space": space("one")]]) == nil, "No spaces")
        precondition(SpaceLayout.parse([["Display Identifier": "A", "Spaces": [space("one")]]]) == nil, "No current space")
        precondition(SpaceLayout.parse([display("A", current: "one", [["uuid": "one"]])]) == nil, "A space without a type")
        precondition(SpaceLayout.parse([display("A", current: "one", [["type": 0]])]) == nil, "A space without a uuid")
        precondition(SpaceLayout.parse([display("A", current: "one", [space("")])]) == nil, "An empty uuid")
        precondition(SpaceLayout.parse([display("A", current: "full", [space("full", type: 4)])]) == nil, "No desktops at all")
        precondition(SpaceLayout.parse([display("A", current: "one", [space("one")]), ["Display Identifier": 3]]) == nil,
                     "One odd display hides it all")
    }

    static func finding() {
        let displays = SpaceLayout.parse([display("AAA", current: "one", [space("one")]),
                                          display("BBB", current: "two", [space("two")])])!
        precondition(SpaceLayout.display(in: displays, matching: "bbb")?.identifier == "BBB", "UUIDs ignore case")
        precondition(SpaceLayout.display(in: displays, matching: nil)?.identifier == "AAA")
        let shared = SpaceLayout.parse([display("Main", current: "one", [space("one")])])!
        precondition(SpaceLayout.display(in: shared, matching: "BBB")?.identifier == "Main", "Shared Spaces cover every display")
        precondition(SpaceLayout.display(in: [], matching: "BBB") == nil)
    }

    static func changing() {
        func parsed(_ current: String, _ uuids: [String] = ["one", "two"]) -> [SpaceDisplay] {
            SpaceLayout.parse([display("A", current: current, uuids.map { space($0, type: $0 == "full" ? 4 : 0) })])!
        }
        let moved = SpaceLayout.changes(from: parsed("one"), to: parsed("two"))
        precondition(moved == [SpaceChange(display: "A", desktop: SpaceDesktop(uuid: "two", number: 2))])
        precondition(SpaceLayout.changes(from: parsed("one"), to: parsed("one")).isEmpty, "Nothing moved")
        precondition(SpaceLayout.changes(from: parsed("two"), to: parsed("two", ["two", "one"])).isEmpty, "Reordering isn't a change")
        precondition(SpaceLayout.changes(from: parsed("one", ["one", "full"]), to: parsed("full", ["one", "full"])).isEmpty,
                     "Going full screen shows nothing")
        precondition(SpaceLayout.changes(from: parsed("full", ["one", "full"]), to: parsed("one", ["one", "full"])).count == 1,
                     "Coming back from full screen does")
        precondition(SpaceLayout.changes(from: [], to: parsed("one")).isEmpty, "A display new to the list isn't a change")
    }

    static func shortcuts() {
        let left = SpaceShortcut(key: 123, flags: 0x840000), right = SpaceShortcut(key: 124, flags: 0x840000)
        let none = SpaceLayout.shortcuts(from: nil)
        precondition(none.left == left && none.right == right && none.desktops.isEmpty, "macOS's defaults when nothing is written")
        // What this macOS really writes for an untouched shortcut: on, with no keys.
        let untouched = SpaceLayout.shortcuts(from: ["79": ["enabled": 1], "81": ["enabled": 1]])
        precondition(untouched.left == left && untouched.right == right)
        let off = SpaceLayout.shortcuts(from: ["79": ["enabled": 0], "81": ["enabled": false]])
        precondition(off.left == nil && off.right == nil, "Switched off")
        let custom: [String: Any] = [
            "81": ["enabled": 1, "value": ["parameters": [65535, 2, 1048576], "type": "standard"]],
            "118": ["enabled": 1, "value": ["parameters": [49, 18, 262144], "type": "standard"]],
            "119": ["enabled": 0, "value": ["parameters": [50, 19, 262144], "type": "standard"]],
            "120": ["enabled": 1, "value": ["parameters": [65535, 65535, 0], "type": "standard"]],
        ]
        let read = SpaceLayout.shortcuts(from: custom)
        precondition(read.right == SpaceShortcut(key: 2, flags: 1048576), "The user's own keys")
        precondition(read.desktops == [1: SpaceShortcut(key: 18, flags: 262144)], "Only switched-on desktops with a real key")
        precondition(SpaceLayout.shortcuts(from: ["79": "nonsense"]).left == left, "An odd entry stands for the default")
    }

    static func jumping() {
        let keys = SpaceShortcuts(left: SpaceShortcut(key: 1, flags: 0), right: SpaceShortcut(key: 2, flags: 0))
        let display = SpaceLayout.parse([display("A", current: "two", [space("one"), space("two"), space("full", type: 4), space("three")])])![0]
        let one = display.desktops[0], two = display.desktops[1], three = display.desktops[2]
        func plan(_ to: SpaceDesktop, on: SpaceDisplay = display, displays: Int = 1, _ shortcuts: SpaceShortcuts = keys) -> SpaceJump {
            SpaceLayout.jump(on: on, to: to, displayCount: displays, shortcuts: shortcuts)
        }
        precondition(plan(two) == .nothing, "Already there")
        precondition(plan(one) == .press(keys.left!, times: 1))
        precondition(plan(three) == .press(keys.right!, times: 2), "Moving passes through the full-screen space")
        precondition(plan(SpaceDesktop(uuid: "gone", number: 9)) == .nothing, "A desktop since removed")
        var direct = keys
        direct.desktops[3] = SpaceShortcut(key: 20, flags: 0)
        precondition(plan(three, direct) == .press(SpaceShortcut(key: 20, flags: 0), times: 1), "Its own shortcut comes first")
        precondition(plan(three, displays: 2, direct) == .press(keys.right!, times: 2), "Desktop numbers span displays")
        var noRight = keys
        noRight.right = nil
        precondition(plan(three, noRight) == .noShortcut)
        precondition(plan(one, noRight) == .press(keys.left!, times: 1), "The other way still works")
        let onFull = SpaceLayout.parse([Self.display("A", current: "full", [space("one"), space("full", type: 4)])])![0]
        precondition(plan(onFull.desktops[0], on: onFull) == .press(keys.left!, times: 1), "Leaving a full-screen space")
    }

    static func words() {
        precondition(SpaceLayout.label(number: 2, name: "Writing") == "2 · Writing")
        precondition(SpaceLayout.label(number: 2, name: nil) == "2")
        precondition(SpaceLayout.label(number: 2, name: "") == "2")
        precondition(SpaceLayout.cleaned(name: "  Writing \n") == "Writing")
        precondition(SpaceLayout.cleaned(name: "a\nb") == "a b", "One line")
        precondition(SpaceLayout.cleaned(name: String(repeating: "x", count: 40)).count == SpaceLayout.nameLimit)
        precondition(SpaceLayout.cleaned(name: String(repeating: "x", count: 19) + " y") == String(repeating: "x", count: 19),
                     "Cutting doesn't leave a trailing space")
        precondition(SpaceLayout.cleaned(name: "   ").isEmpty)
    }
}
