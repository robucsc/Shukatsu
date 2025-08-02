//
//  InterApp.swift
//  Shukatsu
//
//  Created by rob on 9/13/25.
//


import AppKit

enum InterApp {
    enum Pages {
        @MainActor static func open(text: String) {
            let bundleID = "com.apple.iWork.Pages"
            
            // Launch Pages if it's not running (avoid localized name issues)
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, error in
                    if let error { NSLog("Launch Pages error: %@", String(describing: error)) }
                }
            }
            
            // Wait briefly for Pages to start (max ~5s)
            let start = Date()
            while NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
                  Date().timeIntervalSince(start) < 5 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            
            // Escape text for AppleScript string literal
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            
            // Use application id (bundle id) in AppleScript to avoid name mismatches
            let script = """
            tell application id "\(bundleID)"
                if it is not running then launch
                activate
                delay 1.0
                make new document with properties {body text:"\(escaped)"}
            end tell
            """
            let appleScript = NSAppleScript(source: script)
            var err: NSDictionary?
            appleScript?.executeAndReturnError(&err)
            if let err, (err["NSAppleScriptErrorNumber"] as? Int) == -600 {
                Thread.sleep(forTimeInterval: 0.4)
                var err2: NSDictionary?
                appleScript?.executeAndReturnError(&err2)
                if let err2 { NSLog("Pages AppleScript retry error: %@", err2) }
            }
            if let err { NSLog("Pages AppleScript error: %@", err) }
        }
    }
}
