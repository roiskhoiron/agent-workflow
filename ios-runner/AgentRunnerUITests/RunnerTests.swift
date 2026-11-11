import XCTest

// Menjalankan steps.json (base64 di env AGENT_STEPS, dikirim ios-ui.sh lewat TEST_RUNNER_AGENT_STEPS).
// Format langkah dan contoh: skills/_shared/devices.md bagian "iOS: XCUITest runner".
final class RunnerTests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testRun() throws {
        continueAfterFailure = false
        guard let b64 = ProcessInfo.processInfo.environment["AGENT_STEPS"],
              let data = Data(base64Encoded: b64),
              let steps = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return XCTFail("AGENT_STEPS kosong atau bukan array JSON") }
        for (i, step) in steps.enumerated() {
            do { try run(step) } catch {
                shot("fail-step\(i + 1)")
                return XCTFail("langkah \(i + 1) \(step): \(error)")
            }
        }
    }

    private struct StepError: Error, CustomStringConvertible { let description: String }

    private func run(_ s: [String: Any]) throws {
        let timeout = s["timeout"] as? Double ?? 10
        if let id = s["launch"] as? String {
            app = XCUIApplication(bundleIdentifier: id); app.terminate(); app.launch()
        } else if let id = s["activate"] as? String {
            app = XCUIApplication(bundleIdentifier: id); app.activate()
        } else if let sel = s["tap"] as? [String: Any] {
            try find(sel, timeout).tap()
        } else if let p = s["tapAt"] as? [Double], p.count == 2 {
            // label di dalam cell kadang tanpa hit point (Activation point invalid): tap koordinat point dari hierarchy
            try current().coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p[0], dy: p[1])).tap()
        } else if let sel = s["longPress"] as? [String: Any] {
            try find(sel, timeout).press(forDuration: s["duration"] as? Double ?? 1)
        } else if let text = s["type"] as? String {
            if let sel = s["into"] as? [String: Any] { try find(sel, timeout).tap() }
            try current().typeText(text)
        } else if let dir = s["swipe"] as? String {
            let el = try (s["on"] as? [String: Any]).map { try find($0, timeout) } ?? current()
            switch dir {
            case "up": el.swipeUp()
            case "down": el.swipeDown()
            case "left": el.swipeLeft()
            case "right": el.swipeRight()
            default: throw StepError(description: "swipe harus up|down|left|right")
            }
        } else if let sel = s["assert"] as? [String: Any] {
            _ = try find(sel, timeout)
        } else if let label = s["alert"] as? String {
            let b = springboard.buttons[label]
            guard b.waitForExistence(timeout: timeout) else { throw StepError(description: "alert '\(label)' tidak muncul") }
            b.tap()
        } else if let name = s["screenshot"] as? String {
            shot(name)
        } else if let name = s["elementShot"] as? String, let sel = s["of"] as? [String: Any] {
            attach(XCTAttachment(screenshot: try find(sel, timeout).screenshot()), name)
        } else if let name = s["hierarchy"] as? String {
            try hierarchy(name)
        } else if let kind = s["measure"] as? String {
            try measure(kind, s, timeout)
        } else {
            throw StepError(description: "aksi tidak dikenal")
        }
    }

    private func current() throws -> XCUIApplication {
        guard let app else { throw StepError(description: "belum ada launch/activate") }
        return app
    }

    // sel: {"id": accessibilityIdentifier} | {"label": label persis} | {"text": label/value mengandung, tanpa beda huruf besar} | {"placeholder": placeholder persis}
    private func find(_ sel: [String: Any], _ timeout: Double) throws -> XCUIElement {
        let all = try current().descendants(matching: .any)
        let q: XCUIElementQuery
        if let id = sel["id"] as? String { q = all.matching(identifier: id) }
        else if let l = sel["label"] as? String { q = all.matching(NSPredicate(format: "label == %@", l)) }
        else if let t = sel["text"] as? String { q = all.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", t, t)) }
        else if let p = sel["placeholder"] as? String { q = all.matching(NSPredicate(format: "placeholderValue == %@", p)) }
        else { throw StepError(description: "selector harus id|label|text|placeholder") }
        let el = q.element(boundBy: sel["index"] as? Int ?? 0)
        guard el.waitForExistence(timeout: timeout) else { throw StepError(description: "elemen \(sel) tidak ditemukan") }
        return el
    }

    private func shot(_ name: String) { attach(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), name) }

    private func attach(_ a: XCTAttachment, _ name: String) {
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    // <name>.txt = pohon lengkap; <name>-frames.json = elemen + frame dalam piksel screenshot (langsung untuk annotate.py)
    private func hierarchy(_ name: String) throws {
        let a = try current()
        attach(XCTAttachment(string: a.debugDescription), name)
        let img = XCUIScreen.main.screenshot().image
        let scale = img.size.width * img.scale / a.frame.width
        var out: [[String: Any]] = []
        func walk(_ e: XCUIElementSnapshot) {
            let f = e.frame
            if !f.isEmpty && (!e.identifier.isEmpty || !e.label.isEmpty || e.value != nil) {
                out.append(["type": e.elementType.rawValue, "id": e.identifier, "label": e.label,
                            "value": e.value.map { "\($0)" } ?? "",
                            "x": Int(f.minX * scale), "y": Int(f.minY * scale),
                            "w": Int(f.width * scale), "h": Int(f.height * scale)])
            }
            e.children.forEach(walk)
        }
        walk(try a.snapshot())
        let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])
        attach(XCTAttachment(data: json, uniformTypeIdentifier: "public.json"), "\(name)-frames")
    }

    // launch: waktu buka app; scroll: kelancaran scroll di elemen "on" (atau layar). Satu measure per run (batas XCTest).
    private func measure(_ kind: String, _ s: [String: Any], _ timeout: Double) throws {
        let a = try current()
        switch kind {
        case "launch":
            measure(metrics: [XCTApplicationLaunchMetric()]) { a.terminate(); a.launch() }
        case "scroll":
            let el = try (s["on"] as? [String: Any]).map { try find($0, timeout) } ?? a
            let opt = XCTMeasureOptions(); opt.invocationOptions = [.manuallyStop]
            measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: opt) {
                el.swipeUp(velocity: .fast); stopMeasuring(); el.swipeDown(velocity: .fast)
            }
        default:
            throw StepError(description: "measure harus launch|scroll")
        }
    }
}
