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
            .padding()
            
            
            

            
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

