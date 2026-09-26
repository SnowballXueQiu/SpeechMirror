import AVFoundation
import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "speechmirror/device_analysis",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "analyzeVideo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          let durationMs = arguments["duration_ms"] as? NSNumber
        else {
          result(FlutterError(code: "invalid_arguments", message: "Missing video path", details: nil))
          return
        }
        Self.analyzeVideo(path: path, durationMs: durationMs.intValue, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func analyzeVideo(path: String, durationMs: Int, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: path) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "video_missing", message: "Local video was not found", details: nil))
        }
        return
      }

      let asset = AVURLAsset(url: url)
      let assetSeconds = CMTimeGetSeconds(asset.duration)
      let requestedSeconds = Double(max(durationMs, 1)) / 1_000.0
      let duration = assetSeconds.isFinite && assetSeconds > 0
        ? min(assetSeconds, requestedSeconds)
        : requestedSeconds
      let sampleCount = min(120, max(4, Int(ceil(duration / 2.5))))
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 480, height: 480)
      generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
      generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

      var samples: [[String: Any]] = []
      for index in 0..<sampleCount {
        autoreleasepool {
          let seconds = duration * (Double(index) + 0.5) / Double(sampleCount)
          let time = CMTime(seconds: seconds, preferredTimescale: 600)
          guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return
          }
          let request = VNDetectFaceRectanglesRequest()
          let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
          guard
            (try? handler.perform([request])) != nil,
            let faces = request.results,
            let face = faces.max(by: {
              $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
            })
          else {
            samples.append([
              "timestamp_ms": Int(seconds * 1_000),
              "face_detected": false,
              "gaze_centered": 0.0,
              "posture_score": 0.0,
            ])
            return
          }

          let bounds = face.boundingBox
          let horizontalOffset = abs(bounds.midX - 0.5) / 0.38
          let verticalOffset = abs(bounds.midY - 0.58) / 0.48
          let centered = clamp01(1.0 - (horizontalOffset + verticalOffset) * 0.5)
          let yaw = abs(face.yaw?.doubleValue ?? 0)
          let roll = abs(face.roll?.doubleValue ?? 0)
          let frontal = clamp01(1.0 - yaw / 0.55)
          let stable = clamp01(1.0 - roll / 0.35)
          let framing = bounds.width >= 0.16 && bounds.width <= 0.72 ? 1.0 : 0.55
          let singleFace = faces.count == 1 ? 1.0 : 0.72

          samples.append([
            "timestamp_ms": Int(seconds * 1_000),
            "face_detected": true,
            "gaze_centered": clamp01(frontal * 0.7 + centered * 0.3),
            "posture_score": clamp01(centered * 0.55 + stable * 0.25 + framing * 0.2) * singleFace,
          ])
        }
      }

      DispatchQueue.main.async { result(samples) }
    }
  }

  private static func clamp01(_ value: Double) -> Double {
    min(1.0, max(0.0, value))
  }
}
