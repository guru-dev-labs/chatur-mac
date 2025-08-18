# streaming_latency_test.py (Version 8 - With Debug Print)

import os
import asyncio
import sys
import json
from dotenv import load_dotenv
from groq import Groq
from deepgram import DeepgramClient, LiveTranscriptionEvents, LiveOptions
from pathlib import Path

# --- Configuration ---
# This makes the script self-aware. It finds the .env file located in the
# same directory as the script itself, ensuring it works no matter where
# it's run from. This is critical for running inside the Mac app bundle.
script_dir = Path(__file__).parent
dotenv_path = script_dir / '.env'
load_dotenv(dotenv_path=dotenv_path)

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

# --- Transcript Management ---
# A helper class to collect the transcript segments as they arrive from Deepgram.
class TranscriptCollector:
    def __init__(self):
        self.segments = []
    
    # This callback must be 'async' as the SDK expects to 'await' it.
    async def on_message(self, _, result, **kwargs):
        if result.is_final and result.channel.alternatives[0].transcript != '':
            self.segments.append(result.channel.alternatives[0].transcript)
            
    def get_full_transcript(self):
        return " ".join(self.segments)

# --- Output Formatting ---
# A helper function to create a structured JSON string from a Python dictionary.
# This is how we send structured data (e.g. transcripts vs suggestions) back to Swift.
def create_json_output(type, data):
    print(json.dumps({"type": type, "data": data}) + "\n")

# --- Main Application Logic ---
async def main():
    try:
        # Check if API keys are loaded, if not, raise a clear error.
        if not DEEPGRAM_API_KEY:
            raise ValueError("DEEPGRAM_API_KEY is not loaded. Check your .env file.")
        if not GROQ_API_KEY:
            raise ValueError("GROQ_API_KEY is not loaded. Check your .env file.")

        # Initialize the API clients.
        deepgram = DeepgramClient(DEEPGRAM_API_KEY)
        groq_client = Groq(api_key=GROQ_API_KEY)
        
        # Prepare the WebSocket connection.
        dg_connection = deepgram.listen.asyncwebsocket.v("1")
        transcript_collector = TranscriptCollector()
        dg_connection.on(LiveTranscriptionEvents.Transcript, transcript_collector.on_message)
        options = LiveOptions(model="nova-2", language="en-US", smart_format=True)
        await dg_connection.start(options)
        
        # All debug messages are printed to stderr, so stdout remains clean for the JSON output.
        print("Python: Script is now listening for a live audio stream from stdin...", file=sys.stderr)
        
        # This loop reads the raw audio data coming in from the Swift app.
        while True:
            # Read a chunk of binary data from standard input.
            chunk = sys.stdin.buffer.read(4096)

            # --- DEBUG PRINT ---
            # This is our new debug line. It prints the size of the chunk it just received.
            # This confirms that data is successfully flowing from Swift into this script.
            print(f"Python: Received chunk of size {len(chunk)}", file=sys.stderr)
            
            # When the chunk is empty, it means the stream has been closed by the Swift app.
            if not chunk:
                break
            
            # Send the received audio chunk to Deepgram for transcription.
            await dg_connection.send(chunk)
        
        print("Python: Stream finished. Finalizing transcript...", file=sys.stderr)
        
        # Wait for Deepgram to process the final audio and send back the last transcript segments.
        await dg_connection.finish()
        full_transcript = transcript_collector.get_full_transcript()
        
        if full_transcript:
            # Send the final transcript back to Swift as a JSON object.
            create_json_output("final_transcript", full_transcript)
            
            # Call the Groq LLM for suggestions.
            chat_completion = groq_client.chat.completions.create(
                messages=[{"role": "system", "content": "You are an AI assistant..."}, {"role": "user", "content": full_transcript}],
                model="llama3-8b-8192",
            )
            llm_suggestion = chat_completion.choices[0].message.content
            
            # Send the suggestion back to Swift as a JSON object.
            create_json_output("suggestion", llm_suggestion)

    except Exception as e:
        # If any error occurs, send it back as a structured JSON error message.
        error_message = {"type": "error", "data": str(e)}
        print(json.dumps(error_message) + "\n", file=sys.stderr)

if __name__ == "__main__":
    asyncio.run(main())