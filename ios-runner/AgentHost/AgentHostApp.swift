import SwiftUI

// Host kosong: XCUITest butuh app target; app yang diuji dipilih lewat bundle id di steps.json.
@main
struct AgentHostApp: App {
    var body: some Scene {
        WindowGroup { Text("agent-workflow ios-runner") }
    }
}
