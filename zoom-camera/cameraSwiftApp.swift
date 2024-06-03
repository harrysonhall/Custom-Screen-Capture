//
//  cameraSwiftApp.swift
//  cameraSwift
//
//  Created by Harrison Hall on 5/26/24.
//

import SwiftUI

@main
struct cameraSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 724)
                .background(.black)
                .onAppear {
                    if let bundleIdentifier = Bundle.main.bundleIdentifier {
                            let defaultsPath = NSHomeDirectory() + "/Library/Preferences/" + bundleIdentifier + ".plist"
                            print("User defaults file path: \(defaultsPath)")
                        } else {
                            print("Could not determine bundle identifier.")
                        }
                }
        }
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        cleanupBeforeExit()
    }

    private func cleanupBeforeExit() {
        // Your cleanup code here
        print("Application is about to terminate. Performing cleanup.")
        // For example, save user preferences, close files, release resources, etc.
    }
}
