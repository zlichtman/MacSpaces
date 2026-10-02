import Foundation

/// Synthetic agents-channel replies from design/MACSPACES-AGENTS-TAB.md (Tsukumo repo), for QA
/// captures and checks. Never real content.
enum AgentsFixtures {
    static let list = #"""
    {"channel":"agents","version":3,"epoch":"9F1C2A3B-4D5E-4F60-8A7B-1C2D3E4F5A6B","cursor":42,"reset":true,"agents":[
     {"id":"6B656D6F-5361-6265-0000-000000000001","name":"KemoSabe","job":"Your secure assistant, on this Mac","engine":"kemosabe","engineName":"KemoSabe",
      "character":{"shape":"kemosabe","body":"F5E7CF","accent":"EF705B","ink":"211B2C","eyes":"dots","prop":"none"},"state":"idle","canSend":true},
     {"id":"6B656D6F-0000-4000-8000-000000000002","name":"Sample coder","job":"A sample app","engine":"codex","engineName":"Codex",
      "character":{"shape":"gumdrop","body":"E2D9F5","accent":"8563BD","ink":"252039","eyes":"visor","prop":"hardHat"},"state":"working","canSend":false,
      "work":{"status":"Working","headline":"2 of 4: Update the estimator","step":2,"steps":4,"progress":0.25,"file":"Estimator.swift:42","tests":"running","ready":false,"access":"edit","follow":true}},
     {"id":"6B656D6F-0000-4000-8000-000000000003","name":"Study buddy","job":"Tracks sample deadlines","engine":"claude-code","engineName":"Claude Code",
      "character":{"shape":"pebble","body":"A7DCD8","accent":"235D70","ink":"112B34","eyes":"sparkle","prop":"pencil"},"state":"chirping","canSend":true},
     {"id":"6B656D6F-0000-4000-8000-000000000004","name":"Reader","job":"Reads sample papers","engine":"muse","engineName":"Muse Code",
      "character":{"shape":"mochi","body":"91AD94","accent":"344C3F","ink":"182622","eyes":"ovals","prop":"glasses"},"state":"thinking","canSend":false},
     {"id":"6B656D6F-0000-4000-8000-000000000005","name":"Site helper","job":"A sample website","engine":"cursor-agent","engineName":"Cursor Agent",
      "character":{"shape":"block","body":"CFA3CA","accent":"663C6B","ink":"2F1D33","eyes":"dots","prop":"paintbrush"},"state":"needsYou","canSend":false,
      "work":{"status":"Needs you","headline":"Needs your OK: npm test","ready":false,"access":"edit","follow":true}},
     {"id":"6B656D6F-0000-4000-8000-000000000006","name":"Writer","job":"Sample drafts","engine":"claude-code","engineName":"Claude Code",
      "character":{"shape":"bean","body":"D4D8F2","accent":"7873B6","ink":"202138","eyes":"dots","prop":"book"},"state":"talking","partial":"Here's a sample draft of the opening","canSend":false},
     {"id":"6B656D6F-0000-4000-8000-000000000007","name":"Fixer","job":"Sample servers","engine":"codex","engineName":"Codex",
      "character":{"shape":"sprout","body":"EDC8CC","accent":"AE435C","ink":"2B1923","eyes":"dots","prop":"wrench"},"state":"done","canSend":true,
      "work":{"status":"Review","headline":"Ready for review","step":4,"steps":4,"progress":1,"tests":"passed","ready":true,"access":"edit","follow":true}},
     {"id":"6B656D6F-0000-4000-8000-000000000008","name":"Night owl","job":"A sample podcast","engine":"muse","engineName":"Muse Code",
      "character":{"shape":"bean","body":"F5E5A6","accent":"B47B35","ink":"2A251C","eyes":"ovals","prop":"headset"},"state":"sleeping","canSend":true}],
    "feed":[
     {"id":"F0000000-0000-4000-8000-000000000001","date":"2026-09-30T19:00:00Z","kind":"owner","to":["6B656D6F-0000-4000-8000-000000000002"],"text":"Why does the sample map crash offline?","together":true},
     {"id":"F0000000-0000-4000-8000-000000000002","date":"2026-09-30T19:00:40Z","kind":"reply","agent":"6B656D6F-0000-4000-8000-000000000002","text":"A nil region on first launch. I guard it now. Tests pass.","together":false},
     {"id":"F0000000-0000-4000-8000-000000000003","date":"2026-09-30T19:01:00Z","kind":"chirp","agent":"6B656D6F-0000-4000-8000-000000000003","text":"Your sample assignment is due in 2 hours.","together":false},
     {"id":"F0000000-0000-4000-8000-000000000004","date":"2026-09-30T19:01:05Z","kind":"problem","agent":"6B656D6F-0000-4000-8000-000000000004","text":"Reader stopped.","together":false}]}
    """#

    static let approvals = #"""
    {"channel":"agents","version":3,"approvals":[
     {"id":"a1","agent":"6B656D6F-0000-4000-8000-000000000005","kind":"command","text":"npm test","risky":false,"canAnswerHere":true},
     {"id":"a2","agent":"6B656D6F-0000-4000-8000-000000000002","kind":"command","text":"rm -rf build/cache","risky":true,"reason":"deletes files recursively","canAnswerHere":false}]}
    """#

    static let review = #"""
    {"channel":"agents","version":3,"review":{"agent":"6B656D6F-0000-4000-8000-000000000007","tree":"4b825dc642cb6eb9a060e54bf8d69288fbee4904",
     "files":[{"path":"Sources/Estimator.swift","change":"modified","additions":6,"deletions":2},{"path":"Tests/EstimatorTests.swift","change":"modified","additions":4,"deletions":0}],
     "additions":10,"deletions":2,"truncated":false,"canAccept":true,
     "excerpt":"diff --git a/Sources/Estimator.swift b/Sources/Estimator.swift\n@@ -38,4 +38,8 @@\n-        return base\n+        guard let region else { return fallback }\n+        return base + queue\n"}}
    """#

    static func decode(_ json: String) -> MacSpacesAgents.Response? {
        try? MacSpacesAgents.decoder.decode(MacSpacesAgents.Response.self, from: Data(json.utf8))
    }
}
