//
//  WebSocketClient.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import Foundation
import Combine

class WebSocketClient: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let url = URL(string: "ws://localhost:8765")!
    
    @Published var transcribedText: String = ""
    @Published var llmSuggestion: String = ""
    @Published var isConnected: Bool = false
    
    private var cancellables = Set<AnyCancellable>()

    func connect() {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        print("WebSocket connected.")
        listenForMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("WebSocket disconnected.")
    }

    func sendAudioData(_ data: Data) {
        guard isConnected, let task = webSocketTask else {
            print("Cannot send audio data: WebSocket is not connected.")
            return
        }
        
        task.send(.data(data)) { error in
            if let error = error {
                print("Error sending audio data: \(error.localizedDescription)")
            }
        }
    }

    private func listenForMessages() {
        guard let task = webSocketTask else { return }
        
        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error.localizedDescription)")
                self?.isConnected = false
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleIncomingText(text)
                case .data(let data):
                    print("Received binary data: \(data)")
                @unknown default:
                    fatalError()
                }
                // Continue listening for the next message
                self?.listenForMessages()
            }
        }
    }
    
    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let type = json["type"] as? String,
               type == "final_result" {
                
                let transcript = json["transcribed_text"] as? String ?? "N/A"
                let suggestion = json["llm_suggestion"] as? String ?? "N/A"
                
                DispatchQueue.main.async {
                    self.transcribedText = transcript
                    self.llmSuggestion = suggestion
                }
            }
        } catch {
            print("Error decoding JSON from server: \(error)")
        }
    }
}