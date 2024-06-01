//
//  Config.swift
//  cameraSwift
//
//  Created by Harrison Hall on 5/26/24.
//

import Foundation
import AVFoundation

let kFrameRate: Int = 30
let cameraName = "Swift Sample Camera"
//let fixedCamWidth: Int32 = 3456
//let fixedCamHeight: Int32 = 2234
let fixedCamWidth: Int32 = 1728
let fixedCamHeight: Int32 = 1118
let pixelFormat: OSType = kCVPixelFormatType_32BGRA

// Color space and other properties
let colorPrimaries = kCVImageBufferColorPrimaries_ITU_R_709_2
let transferFunction = kCVImageBufferTransferFunction_ITU_R_709_2
let yCbCrMatrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
