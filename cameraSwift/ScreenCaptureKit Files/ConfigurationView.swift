/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that provides the UI to configure screen capture.
*/

import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Cocoa
import CoreMediaIO
import SystemExtensions

/// The app's configuration user interface.
struct ConfigurationView: View {
    
    private let sectionSpacing: CGFloat = 20
    private let verticalLabelSpacing: CGFloat = 8
    private let alignmentOffset: CGFloat = 10
    
    @ObservedObject var screenRecorder: ScreenRecorder
    @Binding var userStopped: Bool
    
    var body: some View {
        VStack {
            Form {
                HeaderView("Video")
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
                
                // A group that hides view labels.
                Group {
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Capture Type")
                        Picker("Capture", selection: $screenRecorder.captureType) {
                            Text("Display").tag(ScreenRecorder.CaptureType.display)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: verticalLabelSpacing) {
                        Text("Screen Content")
                        Picker("Display", selection: $screenRecorder.selectedDisplay) {
                            ForEach(screenRecorder.availableDisplays, id: \.self) { display in
                                Text(display.displayName).tag(SCDisplay?.some(display))
                            }
                        }
                    }
                }
                .labelsHidden()
                
                Toggle("Exclude sample app from stream", isOn: $screenRecorder.isAppExcluded)
                    .disabled(screenRecorder.captureType == .window)

            }
            
            
            ScrollView {
                VStack {
                    ForEach(screenRecorder.availableApps, id: \.self) { app in
                        AppToggleView(
                            appName: app.applicationName,
                            bundleId: app.bundleIdentifier,
                            isExcluded: !screenRecorder.excludedApplications.contains(app.bundleIdentifier),
                            onToggle: { value in
                                print("new value is: ", value, "bundleID is: ", app.bundleIdentifier)
                                if value {
                                    screenRecorder.excludedApplications.remove(app.bundleIdentifier)
                                } else {
                                    screenRecorder.excludedApplications.insert(app.bundleIdentifier)
                                }
                            }
                        ) {
                            // Use the filtered and sorted windows
                            let appWindows = filteredAndSortedWindows(for: app, windows: screenRecorder.availableWindows)

                            ForEach(appWindows, id: \.self) { window in
                                ToggleRowView(
                                    title: window.title ?? " ",
                                    windowId: Int32(window.windowID),
                                    owningApplicationBundleId: app.bundleIdentifier,
                                    isExcluded: !screenRecorder.excludedWindows.contains("\(app.bundleIdentifier).\(window.title!)"),
                                    onToggle: { value in
                                        print("new value is: ", value, "bundleID is: ", app.bundleIdentifier, "windowId is: ", window.windowID)
                                        if value {
                                            screenRecorder.excludedWindows.remove("\(app.bundleIdentifier).\(window.title!)")
                                        } else {
                                            screenRecorder.excludedWindows.insert("\(app.bundleIdentifier).\(window.title!)")
                                        }
                                    }
                                )
                                .onAppear {
                                    print("window Id:", window.windowID, "title: ", window.title ?? " ")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .border(Color.black)
                }
                .frame(maxWidth: .infinity)
                .border(Color.black)
            }
            

            
            HStack {
                Button { SystemExtensionManager.shared.installExtension() }
                label: { Text("Install Extension") }
                
                
                Button { SystemExtensionManager.shared.uninstallExtension() }
                label: { Text("Uninstall Extension") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
    
            
            
            
            
            
            
            
            
        
            
            Spacer()
            HStack {
                Button {
                    Task { await screenRecorder.start() }
                    // Fades the paused screen out.
                    withAnimation(Animation.easeOut(duration: 0.25)) {
                        userStopped = false
                    }
                } label: {
                    Text("Start Capture")
                }
                .disabled(screenRecorder.isRunning)
                Button {
                    Task { await screenRecorder.stop() }
                    // Fades the paused screen in.
                    withAnimation(Animation.easeOut(duration: 0.25)) {
                        userStopped = true
                    }

                } label: {
                    Text("Stop Capture")
                }
                .disabled(!screenRecorder.isRunning)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .background(MaterialView())
    }
    

    func filteredAndSortedWindows(for app: SCRunningApplication, windows: [SCWindow]) -> [SCWindow] {
        return windows
            .filter { $0.owningApplication?.applicationName == app.applicationName }
            .sorted {
                let title1 = $0.title ?? ""
                let title2 = $1.title ?? ""
                return !title1.isEmpty && (title2.isEmpty || title1 < title2)
            }
    }
}





struct AppToggleView<Content: View>: View {
    let appName: String
    let bundleId: String
    let content: () -> Content?
    let onToggle: (Bool) -> Void
    @State var isToggled: Bool = true
    @State private var appIcon: NSImage?
    
    init(
        appName: String,
        bundleId: String,
        isExcluded: Bool,
        onToggle: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content? = { nil } // Default value for content
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.isToggled = isExcluded
        self.onToggle = onToggle
        self.content = content
        _appIcon = State(initialValue: AppToggleView.getAppIcon(bundleId: bundleId))
    }
    
    var body: some View {
        GroupBox {
            VStack {
                HStack {
                    Button(action: {
                        // Define what happens when the button is clicked
                        print("Button clicked!")
                    }) {
                        HStack {
                            if let icon = appIcon {
                                Image(nsImage: icon)
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)  // Force size to 32x32
                            } else {
                                Image(systemName: "app.fill")
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)  // Force size to 32x32
                            }
                            Text("[ \(appName) ]")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())  // Ensures the whole HStack is tappable
                    }
                    .buttonStyle(PlainButtonStyle()) // Use PlainButtonStyle to remove default button styling
                    .border(Color.black)  // Adds a border to the button
                    
                    Spacer()
                    
                    Toggle("", isOn: $isToggled)
                        .toggleStyle(SwitchToggleStyle())
                        .border(Color.black)  // Adds a border around the Toggle
                        .onChange(of: isToggled) { newValue in
                            onToggle(newValue) // Call the onToggle closure with the new value
                        }
                }
                .border(Color.black)
                
                if let content = content() {
                    content
                        .padding(.leading, 32)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .border(Color.black)
    }
    
    static func getAppIcon(bundleId: String) -> NSImage? {
        guard let path = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}







struct ToggleRowView: View {
    private let title: String
    private let windowId: Int32
    private let owningApplicationBundleId: String
    @State private var isToggled: Bool = false
    let onToggle: (Bool) -> Void
    
    init(
        title: String,
        windowId: Int32,
        owningApplicationBundleId: String,
        isExcluded: Bool,
        onToggle: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.windowId = Int32(windowId)
        self.owningApplicationBundleId = owningApplicationBundleId
        self.isToggled = isExcluded
        self.onToggle = onToggle
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .border(Color.black)

            
            Toggle("", isOn: $isToggled)
                .toggleStyle(SwitchToggleStyle())
                .frame(alignment: .trailing)
                .scaleEffect(0.8)
                .onChange(of: isToggled) { newValue in
                    onToggle(newValue) // Call the onToggle closure with the new value
                }
        }
        .border(Color.black)
    }
}





/// A view that displays a styled header for the Video and Audio sections.
struct HeaderView: View {
    
    private let title: String
    private let alignmentOffset: CGFloat = 10.0
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .alignmentGuide(.leading) { _ in alignmentOffset }
    }
}

