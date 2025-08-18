import SwiftUI
import AVFoundation

// A struct to represent our JSON message from Python.
// 'Codable' allows Swift to easily convert JSON data into this struct.
struct CoPilotMessage: Codable {
    let type: String
    let data: String
}

struct ContentView: View {
    // MARK: - State Properties
    // These properties hold the state of our view. When they change, the UI updates automatically.
    @StateObject private var audioEngine = AudioEngine()
    @State private var pythonProcess: Process?
    @State private var inputPipe: Pipe?
    @State private var finalTranscript: String = "Click 'Start Co-Pilot' to begin..."
    @State private var suggestion: String = "Waiting for suggestions..."
    @State private var isRunning: Bool = false
    @State private var errorMessage: String = ""
    
    // MARK: - Main View Body
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Chatur Co-Pilot")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.primary)
            
            HStack(spacing: 10) {
                Button(action: startCoPilot) {
                    Text("Start Co-Pilot")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(isRunning ? Color.gray : Color.green)
                        .cornerRadius(8)
                }
                .disabled(isRunning)
                
                Button(action: stopCoPilot) {
                    Text("Stop Co-Pilot")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(!isRunning ? Color.gray : Color.red)
                        .cornerRadius(8)
                }
                .disabled(!isRunning)
                
                if isRunning {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .scaleEffect(1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: isRunning)
                        Text("Recording")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            // UI Section for the Transcript
            VStack(alignment: .leading, spacing: 5) {
                Text("📝 Transcript:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                ScrollView {
                    Text(finalTranscript)
                        .font(.body)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            // UI Section for the Suggestions
            VStack(alignment: .leading, spacing: 5) {
                Text("✨ Suggestions:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                ScrollView {
                    Text(suggestion)
                        .font(.body)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
        }
        .frame(width: 500, height: 500)
        .padding(20)
        .onAppear {
            // macOS handles microphone permissions automatically when first accessed
        }
        .onDisappear {
            cleanupResources()
        }
    }

    // MARK: - Core Functions
    func startCoPilot() {
        guard !isRunning else { return }
        
        errorMessage = ""
        finalTranscript = "Initializing..."
        suggestion = "Waiting for suggestions..."
        isRunning = true
        
        // Find Python script in bundle
        guard let scriptPath = Bundle.main.path(forResource: "streaming_latency_test", ofType: "py") else {
            handleError("Could not find Python script in app bundle.")
            return
        }
        
        // Construct path to Python virtual environment
        let scriptURL = URL(fileURLWithPath: scriptPath)
        let pythonEngineURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let pythonPath = pythonEngineURL.appendingPathComponent("venv/bin/python").path
        
        // Verify Python executable exists
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            handleError("Python executable not found at: \(pythonPath)")
            return
        }
        
        // Process and Pipe Setup
        let process = Process()
        process.currentDirectoryURL = pythonEngineURL
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        self.pythonProcess = process
        self.inputPipe = stdinPipe
        
        // Handle process termination
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                self.handleProcessTermination(process)
            }
        }
        
        // Handle stderr for error messages
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let errorStr = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("Python stderr: \(errorStr)")
                    if !errorStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.errorMessage = "Python error: \(errorStr)"
                    }
                }
            }
        }
        
        // Handle stdout for JSON messages
        let lineReader = LineReader(fileHandle: stdoutPipe.fileHandleForReading)
        lineReader.onNewLine = { line in
            self.processJSONMessage(line)
        }
        
        // Setup audio data handler
        audioEngine.audioDataHandler = { data in
            self.sendAudioData(data)
        }
        
        // Start the process
        DispatchQueue.global(qos: .background).async {
            do {
                try process.run()
                
                // Start audio engine after process is confirmed running
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.audioEngine.startListening()
                    self.finalTranscript = "Listening... Speak now!"
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleError("Failed to start Python process: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func stopCoPilot() {
        guard isRunning else { return }
        
        isRunning = false
        finalTranscript = "Stopping..."
        
        // Stop audio engine first
        audioEngine.stopListening()
        
        // Close stdin pipe gracefully
        if let pipe = inputPipe {
            do {
                try pipe.fileHandleForWriting.close()
            } catch {
                print("Error closing stdin pipe: \(error)")
            }
        }
        
        // Terminate process if still running
        if let process = pythonProcess, process.isRunning {
            process.terminate()
            
            // Give it a moment to terminate gracefully
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    process.forceTerminate()
                }
            }
        }
        
        cleanupResources()
        finalTranscript = "Co-pilot stopped."
        suggestion = "Ready to start again."
    }
    
    // MARK: - Helper Functions
    private func handleError(_ message: String) {
        errorMessage = message
        finalTranscript = "Error occurred. See message above."
        isRunning = false
        cleanupResources()
    }
    
    private func handleProcessTermination(_ process: Process) {
        let exitCode = process.terminationStatus
        if exitCode != 0 && isRunning {
            handleError("Python process exited with code: \(exitCode)")
        } else if isRunning {
            finalTranscript = "Process ended unexpectedly."
            isRunning = false
        }
        cleanupResources()
    }
    
    private func processJSONMessage(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        
        do {
            let message = try JSONDecoder().decode(CoPilotMessage.self, from: data)
            DispatchQueue.main.async {
                switch message.type {
                case "final_transcript":
                    self.finalTranscript = message.data
                case "suggestion":
                    self.suggestion = message.data
                case "error":
                    self.handleError(message.data)
                default:
                    print("Unknown message type: \(message.type)")
                }
            }
        } catch {
            print("Failed to decode JSON: \(error), line: \(line)")
        }
    }
    
    private func sendAudioData(_ data: Data) {
        guard isRunning, let pipe = inputPipe else { return }
        
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            print("Error writing audio data to stdin: \(error)")
            DispatchQueue.main.async {
                self.handleError("Failed to send audio data to Python")
            }
        }
    }
    
    private func cleanupResources() {
        pythonProcess = nil
        inputPipe = nil
        errorMessage = ""
    }
}

// MARK: - LineReader Class
class LineReader {
    private let fileHandle: FileHandle
    private var buffer: Data = Data()
    var onNewLine: ((String) -> Void)?

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.fileHandle.readabilityHandler = { handle in
            self.read()
        }
    }

    private func read() {
        let data = fileHandle.availableData
        if data.isEmpty {
            // End of file
            fileHandle.readabilityHandler = nil
        } else {
            buffer.append(data)
            processBuffer()
        }
    }

    private func processBuffer() {
        while let range = buffer.range(of: Data([10])) { // Newline character '\n'
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                onNewLine?(line)
            }
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
        }
    }
}

// MARK: - Process Extension
extension Process {
    func forceTerminate() {
        if isRunning {
            kill(processIdentifier, SIGKILL)
        }
    }
}

#Preview {
    ContentView()
}