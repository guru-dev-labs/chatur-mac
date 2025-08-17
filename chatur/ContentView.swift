//
//  ContentView.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import SwiftUI

struct ContentView: View {
    // @StateObject is used to keep our AudioEngine alive for the entire view lifecycle.
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var webSocketClient = WebSocketClient()
    @State private var isListening = false

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            
            Text("Chatur Co-Pilot")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Visual indicator for listening state
            Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(isListening ? .red : .gray)
                .animation(.spring(), value: isListening)

            Text(webSocketClient.isConnected ? (isListening ? "Listening..." : "Connected") : "Disconnected")
                .font(.headline)
            
            // Display for transcribed text and suggestions
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You said:")
                        .fontWeight(.bold)
                    Text(webSocketClient.transcribedText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    
                    Text("Suggestion:")
                        .fontWeight(.bold)
                    Text(webSocketClient.llmSuggestion)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .frame(height: 150)


            HStack(spacing: 20) {
                // Button to start listening
                Button(action: {
                    webSocketClient.connect()
                    audioEngine.webSocketClient = webSocketClient
                    audioEngine.startListening()
                    isListening = true
                }) {
                    Text("Start Listening")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(isListening) // Disable button when already listening
                
                // Button to stop listening
                Button(action: {
                    audioEngine.stopListening()
                    webSocketClient.disconnect()
                    isListening = false
                }) {
                    Text("Stop Listening")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!isListening) // Disable button when not listening
            }
        }
        .frame(width: 450, height: 450)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}


#Preview {
    ContentView()
}
