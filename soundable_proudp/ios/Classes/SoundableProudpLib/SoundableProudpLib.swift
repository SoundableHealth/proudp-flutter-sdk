// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import AVFoundation

public protocol SoundableProudpLibDelegate: AnyObject {
    func recordingDidCancelDueToCallInterrupt()
}

@available(iOS 13.0, *)
public class SoundableProudpLib: NSObject, AVAudioRecorderDelegate {
    
    private var isRunning: Bool = false
    private var audioRecorder: AVAudioRecorder!
    private var currentFileUrl: URL?
    private var timer: DispatchSourceTimer!
    private var userId = ""
    private var serverUrl = ""
    private var apiKey = ""
    private var websocketUrl = ""
    public static var recordTime = "00:00"
    let maxRecordingTime = 180 // max recording time: 3 minutes
    
    public weak var delegate: SoundableProudpLibDelegate?

    deinit {
        removeAudioSessionNotifications()
    }

    func valueDidChange(_ newValue: Int) {
        print(newValue)
    }
    
    
    private func modelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.replacingOccurrences(of: ",", with: "_")
    }
    
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    
    private func getAudioFileName(userId:String, gender:String, clinic:String) -> String {
        var ret:String
        ret = userId.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression) + "-"
        
        let df:DateFormatter = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        ret += df.string(from: Date())
        
        ret += "-"
        ret += modelName()
        
        var appVersion = "100"
        if let dictionary = Bundle.main.infoDictionary {
            let version = dictionary["CFBundleShortVersionString"] as! String
            appVersion = version.replacingOccurrences(of: ".", with: "")
        }
        ret += "-"
        ret += appVersion
        
        ret += "-"
        ret += gender.lowercased()

        ret += "-"
        ret += clinic.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        
        ret += "-null.m4a"
        return ret
    }
    
    
    private func setTimer() -> Void {
        var time: Int = 0
        
        if self.timer == nil || self.timer!.isCancelled {
            self.timer = DispatchSource.makeTimerSource()
            self.timer?.schedule(deadline: .now(), repeating: .seconds(1))
            self.timer?.setEventHandler {
                if self.isRunning {
                    time += 1
                    SoundableProudpLib.recordTime = String(format: "%02d:%02d", time/60, time%60)
                    print(SoundableProudpLib.recordTime)
                    if time % self.maxRecordingTime == 0 && time > 0 {
                        self.stopRecording()
                    }
                }
            }
        }
    }
    
    public func setServerConfig(serverUrl: String, apiKey: String, websocketUrl: String) {
        print("setServerConfig")
        self.serverUrl = serverUrl
        self.apiKey = apiKey
        self.websocketUrl = websocketUrl
    }
    
    
    public func checkPermission() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            AVAudioSession.sharedInstance().requestRecordPermission { (allowed) in
                DispatchQueue.main.async {
                    if allowed { 
                        print("mic permission is allowed")
                    }
                    else {
                        print("mic permission is not allowed")
                    }
                }
            }
        } catch {
            print("mic permission check error")
        }
    }
    
    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    private func removeAudioSessionNotifications() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("Audio session interruption began (call received)")
            if isRunning {
                cancelRecordingDueToCallInterrupt()
            }
        case .ended:
            print("Audio session interruption ended")
        @unknown default:
            break
        }
    }
    
    private func cancelRecordingDueToCallInterrupt() {
        print("Cancelling recording due to call interrupt")
        cancelRecording()
        delegate?.recordingDidCancelDueToCallInterrupt()
    }
        
    
    public func startRecording(userId:String, gender:String, clinic:String) {
        
        let audioSettings: [String:Int] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        if !self.isRunning {
            self.userId = userId
            let audioFileName = getAudioFileName(userId: userId, gender: gender, clinic: clinic)
            let audioFileUrl = getDocumentsDirectory().appendingPathComponent(audioFileName)
            
            print(audioFileName)
            
            self.currentFileUrl = audioFileUrl
            self.setTimer()
            self.setupAudioSessionNotifications()
            do {
                self.audioRecorder = try AVAudioRecorder(url: audioFileUrl, settings: audioSettings)
                self.audioRecorder.delegate = self
                self.audioRecorder.record()
                self.timer.resume()
                self.isRunning = true
            } catch {
                self.cancelRecording()
            }
        }
    }
    
    
    public func stopRecording() {
        print("stop recording")
        finishRecording(isCancelled: false)
    }
    
    
    public func cancelRecording() {
        print("cancel recording")
        finishRecording(isCancelled: true)
    }
    
    
    private func finishRecording(isCancelled: Bool) -> Void {
        SoundableProudpLib.recordTime = "00:00"

        if self.isRunning {
            if self.audioRecorder != nil {
                self.audioRecorder.stop()
                self.audioRecorder = nil
            }
            
            self.isRunning = false
            self.timer.cancel()
            self.removeAudioSessionNotifications()

            if isCancelled {
                if let currentFileUrl = self.currentFileUrl {
                    self.removeFile(sourceUrl: currentFileUrl)
                }
            }
        }
    }
    
    
    private func removeFile(sourceUrl: URL) -> Void {
        do {
            try FileManager.default.removeItem(at: sourceUrl)
            print("file removed", sourceUrl.lastPathComponent)
            self.currentFileUrl = nil
        } catch {
            print(error.localizedDescription)
        }
    }
    
    
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag == true {
            if let currentFileUrl = self.currentFileUrl {
                NetworkUtil.shared.uploadAudioFile(fileUrl: currentFileUrl, apiKey: self.apiKey, apiUrl: self.serverUrl) {
                    self.removeFile(sourceUrl: currentFileUrl)
                    WebsocketUtil.shared.checkSocketSessionAliveAndTryReconnect(user_id: self.userId, webSocketUrl: self.websocketUrl)
                    
                } fileUploadFail: { errorCode in
                    print("upload fail: ", errorCode)
                }

            }
        } else {
            print("audioRecorderDidFinishRecording error")
        }
    }
}
