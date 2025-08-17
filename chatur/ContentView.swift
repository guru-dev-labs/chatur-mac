//
//  ContentView.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    
    // State for the Python process and its communication pipes
    @State private var pythonProcess: Process?
    @State private var inputPipe: Pipe?
    
    // State to display the final transcript
    @State private var finalTranscript: String = "..."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Chatur Co-Pilot")
                .font(.largeTitle)
            
            Text("Press 'Start' to begin the interview co-pilot. Speak into your microphone and press 'Stop' when you are finished.")
                .foregroundColor(.secondary)
            
            HStack {
                Button("Start Co-Pilot") {
                    startCoPilot()
                }
                
                Button("Stop Co-Pilot") {
                    stopCoPilot()
                }
            }
            
            Divider()
            
            Text("Final Transcript:")
                .font(.headline)
            
            ScrollView {
                Text(finalTranscript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            
        }
        .frame(width: 450, height: 400)
        .padding()
    }

    func startCoPilot() {
        finalTranscript = "Listening..."
        
        // --- 1. Launch the Python Process ---
        let pythonEnginePath = "/Users/magmacray/My Files/Development/Chatur/chatur-mvp"
        let pythonPath = "\(pythonEnginePath)/venv/bin/python"
        let scriptPath = "\(pythonEnginePath)/streaming_latency_test.py"
        
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: pythonEnginePath)
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        
        // --- 2. Setup the Pipes for Communication ---
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        
        self.pythonProcess = process
        self.inputPipe = stdinPipe
        
        // --- 3. Listen for the Final Transcript ---
        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self.finalTranscript = output
                }
            }
        }
        
        // --- 4. Define the Audio Handler ---
        // This is where we connect the AudioEngine to the Python process.
        audioEngine.audioDataHandler = { data in
            do {
                // When we get audio data from the engine, write it to the Python script's stdin.
                try self.inputPipe?.fileHandleForWriting.write(contentsOf: data)
            } catch {
                print("Error writing to stdin: \(error.localizedDescription)")
            }
        }
        
        // --- 5. Run the Process and Start Listening ---
        DispatchQueue.global(qos: .background).async {
            do {
                try process.run()
                audioEngine.startListening()
            } catch {
                DispatchQueue.main.async {
                    self.finalTranscript = "Error: Could not start the Python process."
                }
            }
        }
    }
    
    func stopCoPilot() {
        audioEngine.stopListening()
        
        // Close the pipe to signal the end of the stream to the Python script.
        try? self.inputPipe?.fileHandleForWriting.close()
        
        // Wait for the process to finish
        pythonProcess?.waitUntilExit()
        
        pythonProcess = nil
        inputPipe = nil
        
        print("Co-pilot stopped.")
    }
}

#Preview {
    ContentView()
}
