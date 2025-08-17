//
//  AudioEngine.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import Foundation
import AVFoundation

// This class will manage all the audio recording logic.
class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine?
    var webSocketClient: WebSocketClient?

    // This is the corrected function for macOS
    func startListening() {
        // On macOS, we use AVCaptureDevice to request permission.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: // The user has previously granted access to the microphone.
            DispatchQueue.main.async {
                self.setupAndStartEngine()
            }
        case .notDetermined: // The user has not yet been asked for microphone access.
            AVCaptureDevice.requestAccess(for: .audio) { [unowned self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupAndStartEngine()
                    }
                }
            }
        case .denied: // The user has previously denied access.
            print("Microphone permission was previously denied.")
            return
        case .restricted: // The user can't grant access due to parental controls, etc.
            print("Microphone access is restricted.")
            return
        @unknown default:
            fatalError("Unknown authorization status for audio.")
        }
    }
    
    private func setupAndStartEngine() {
        audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { (buffer, when) in
            if let pcmBuffer = buffer as AVAudioPCMBuffer? {
                let audioData = self.convertAudioBufferToData(pcmBuffer: pcmBuffer)
                self.webSocketClient?.sendAudioData(audioData)
            }
        }
        
        audioEngine!.prepare()
        do {
            try audioEngine!.start()
            print("Audio engine started successfully.")
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }
    
    func stopListening() {
        guard let engine = audioEngine, engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        self.audioEngine = nil
        print("Audio engine stopped.")
    }

    private func convertAudioBufferToData(pcmBuffer: AVAudioPCMBuffer) -> Data {
        let channelCount = 1  // mono
        let channels = UnsafeBufferPointer(start: pcmBuffer.int16ChannelData, count: channelCount)
        let ch0Data = NSData(bytes: channels[0], length: Int(pcmBuffer.frameLength * 2)) as Data
        return ch0Data
    }
}
