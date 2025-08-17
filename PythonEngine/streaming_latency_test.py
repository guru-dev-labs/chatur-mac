# streaming_latency_test.py (Version 7 - Self-Aware Path)

import os
import asyncio
import sys
import json
from dotenv import load_dotenv
from groq import Groq
from deepgram import DeepgramClient, LiveTranscriptionEvents, LiveOptions
from pathlib import Path # Import the Path object from pathlib

# --- KEY CHANGE: Make the script self-aware about its location ---
# Get the directory of the currently running script.
script_dir = Path(__file__).parent
# Create the full path to the .env file located in the same directory.
dotenv_path = script_dir / '.env'
# Load the .env file from that specific path.
load_dotenv(dotenv_path=dotenv_path)

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

class TranscriptCollector:
    # ... (This class remains unchanged)
    def __init__(self):
        self.segments = []
    async def on_message(self, _, result, **kwargs):
        if result.is_final and result.channel.alternatives[0].transcript != '':
            self.segments.append(result.channel.alternatives[0].transcript)
    def get_full_transcript(self):
        return " ".join(self.segments)

def create_json_output(type, data):
    # ... (This function remains unchanged)
    print(json.dumps({"type": type, "data": data}) + "\n")

async def main():
    # ... (This entire function remains unchanged)
    try:
        # Check if API keys are loaded
        if not DEEPGRAM_API_KEY or not GROQ_API_KEY:
            raise ValueError("API keys for Deepgram or Groq are not loaded. Check your .env file.")

        deepgram = DeepgramClient(DEEPGRAM_API_KEY)
        groq_client = Groq(api_key=GROQ_API_KEY)
        dg_connection = deepgram.listen.asyncwebsocket.v("1")
        
        transcript_collector = TranscriptCollector()
        dg_connection.on(LiveTranscriptionEvents.Transcript, transcript_collector.on_message)

        options = LiveOptions(model="nova-2", language="en-US", smart_format=True)
        await dg_connection.start(options)
        
        while True:
            chunk = sys.stdin.buffer.read(4096)
            if not chunk:
                break
            await dg_connection.send(chunk)
        
        await dg_connection.finish()
        full_transcript = transcript_collector.get_full_transcript()
        
        if full_transcript:
            create_json_output("final_transcript", full_transcript)
            
            chat_completion = groq_client.chat.completions.create(
                messages=[{"role": "system", "content": "You are an AI assistant..."}, {"role": "user", "content": full_transcript}],
                model="llama3-8b-8192",
            )
            llm_suggestion = chat_completion.choices[0].message.content
            create_json_output("suggestion", llm_suggestion)

    except Exception as e:
        error_message = {"type": "error", "data": str(e)}
        print(json.dumps(error_message) + "\n", file=sys.stderr)

if __name__ == "__main__":
    asyncio.run(main())
