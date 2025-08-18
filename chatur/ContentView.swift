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
    // Replace the startCoPilot function in ContentView.swift with this self-contained version.

func startCoPilot() {
        // Reset state and UI
        finalTranscript = "Initializing Co-Pilot Engine..."
        suggestion = "..."
        errorMessage = ""
        isRunning = true // Set isRunning to true at the start

        // --- Find Bundled Python Resources ---
        guard let resourcePath = Bundle.main.resourcePath else {
            handleError("Could not find app's resource path.")
            return
        }
        
        let pythonEnginePath = "\(resourcePath)/python_engine"
        let pythonPath = "/usr/bin/python3"
        let scriptPath = "\(pythonEnginePath)/streaming_latency_test.py"

        // --- Process and Pipe Setup ---
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: pythonEnginePath)
        
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = pythonEnginePath
        process.environment = environment
        
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe() // Capture stderr for debugging
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe // Assign stderr pipe
        
        self.pythonProcess = process
        self.inputPipe = stdinPipe
        
        // --- Stderr Handling ---
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                print("Python stderr: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // --- Stdout Handling (JSON Messages) ---
        let reader = LineReader(fileHandle: stdoutPipe.fileHandleForReading)
        reader.onNewLine = { [weak self] line in
            self?.processJSONMessage(line)
        }
        self.lineReader = reader
        
        // --- Process Termination Handler ---
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleProcessTermination(process)
            }
        }
        
        // --- Audio Engine Setup ---
        audioEngine.audioDataHandler = { [weak self] data in
            self?.sendAudioData(data)
        }
        
        // --- Start Process and Audio Engine ---
        DispatchQueue.global(qos: .background).async {
            do {
                try process.run()
                self.audioEngine.startListening()
            } catch {
                DispatchQueue.main.async {
                    self.handleError("Could not start the Python process: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func stopCoPilot() {
        guard isRunning else { return }
        
        finalTranscript = "Stopping..."
        
        // Stop audio engine first to prevent writing to a closed pipe
        audioEngine.stopListening()
        
        // Close stdin pipe gracefully to signal end of stream to Python
        if let pipe = inputPipe {
            do {
                try pipe.fileHandleForWriting.close()
            } catch {
                // This error is common if the process already terminated, so we just log it.
                print("Error closing stdin pipe: \(error.localizedDescription)")
            }
        }
        
        // Terminate process if it's still running after a short delay
        if let process = pythonProcess, process.isRunning {
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    process.terminate() // Ask nicely first
                }
            }
        }
        
        // The termination handler will call cleanupResources and update the state.
        // We set isRunning to false here to update the UI immediately.
        isRunning = false
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
        lineReader = nil // Deallocate line reader
    }
    
    // Add a property to hold the LineReader instance
    @State private var lineReader: LineReader?
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
