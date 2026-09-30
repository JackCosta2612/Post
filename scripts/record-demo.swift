import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation

@available(macOS 15.0, *)
final class Delegate: NSObject, SCRecordingOutputDelegate {
    var finished = false
    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        print("RECORDING \(Date().timeIntervalSince1970)"); fflush(stdout)
    }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { finished = true }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) { print("FAILED \(error)"); finished = true }
}
@main struct Recorder {
    static func main() async throws {
        guard #available(macOS 15.0, *) else { return }
        _ = NSApplication.shared
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "com.jack.Post.demo" && $0.title == "Post" }) else {
            print("No Post Demo window"); return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false; config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        let background = CGColor(red: 0.969, green: 0.969, blue: 0.929, alpha: 1)
        config.backgroundColor = background
        let delegate = Delegate()
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        recording.videoCodecType = .h264; recording.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recording, delegate: delegate)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(output)
        print("WINDOW \(window.frame) SIZE \(config.width)x\(config.height)"); fflush(stdout)
        try await stream.startCapture()
        let end = Date().addingTimeInterval(600)
        while Date() < end && !FileManager.default.fileExists(atPath: CommandLine.arguments[2]) && !delegate.finished {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await stream.stopCapture()
        for _ in 0..<100 where !delegate.finished { try await Task.sleep(nanoseconds: 100_000_000) }
        print("FINISHED")
    }
}
