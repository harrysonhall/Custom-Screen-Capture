//
//  VirtualCameraView.swift
//  cameraSwift
//
//  Created by Harrison Hall on 6/1/24.
//

import Foundation
import SwiftUI
import AVFoundation
import AppKit

class CameraViewController: NSViewController {
    
    
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var virtualCamera: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        // Filter and find the device that we would like to use to render to the view layer
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
            print("deivces localized name is: ", device.localizedName == cameraName)
            virtualCamera = device
        }
    
        guard let selectedVirtualCamera = virtualCamera,
              let input = try? AVCaptureDeviceInput(device: selectedVirtualCamera),
              captureSession?.canAddInput(input) == true else {
            return
        }

        captureSession?.addInput(input)

        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        videoPreviewLayer?.videoGravity = .resizeAspect

        
        let dimensions = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
        Utility.aspectRatio = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        
        if view.layer == nil {
            view.layer = CALayer()
        }

        if let layer = view.layer {
            videoPreviewLayer?.frame = layer.bounds
            print("layer bounds from up here are: ", layer.bounds)
            layer.addSublayer(videoPreviewLayer!)
        }

        captureSession?.startRunning()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        
        if let layer = view.layer {
            videoPreviewLayer?.frame = layer.bounds
            print("frame is: ", videoPreviewLayer?.frame)
            print("layer bounds are: ", layer.bounds)
        }
    }
}

struct CameraView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }

    func updateNSViewController(_ nsViewController: CameraViewController, context: Context) {
        // No updates needed for now
    }
}


class Utility {
    static var aspectRatio = CGSize(width: 1, height: 1)
    static var renderVirtualCameraPreview = false
    static var virtualCamera: AVCaptureDevice?
    static var listOfDevices: [String] {
        var deviceNames: [String] = []
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        for device in discoverySession.devices {
            deviceNames.append(device.localizedName)
        }
        return deviceNames
    }
    
}
