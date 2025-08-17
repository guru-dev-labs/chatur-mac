//
//  AudioEngine.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import Foundation
import AVFoundation

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine?
    
    // This is a new property. It's a "closure" or a function that we can set from ContentView.
    // It will be called every time a new audio buffer is available.
    var audioDataHandler: ((Data) -> Void)?
    
    func startListening() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.setupAndStartEngine()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [unowned self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupAndStartEngine()
                    }
                }
            }
        // ... (rest of the cases are the same)
        case .denied, .restricted:
            print("Microphone permission is not available.")
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
            // --- KEY CHANGE ---
            // Instead of printing, we now convert the buffer to raw Data.
            // This is complex, but it essentially gets the raw bytes of the audio.
            let audioData = self.bufferToData(buffer: buffer)
            
            // We then call our handler, passing the raw audio data back to ContentView.
            self.audioDataHandler?(audioData)
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
    
    // Helper function to convert the audio buffer to a Data object
    private func bufferToData(buffer: AVAudioPCMBuffer) -> Data {
        let channelCount = 1  // 1 for mono
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: channelCount)
        let data = Data(bytes: channels[0], count: Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame))
        return data
    }
}
