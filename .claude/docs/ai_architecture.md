# AI Architecture & Capabilities

The LotusHaven AI Assistant is a Voice-First overlay designed for ease of use by the elderly, particularly veterans.

## The Voice-First Overlay (AssistantBubble)

*   **Design:** A persistent Floating Action Button (FAB), 64x64 dp, using a soft animation (`support.gif`).
*   **Presence:** Appears on **EVERY** screen in the application.
*   **Interaction:** 
    *   User taps the button → Chime sound plays to indicate readiness.
    *   Microphone auto-records user speech.
    *   User taps again to stop recording.
    *   Audio payload is sent to the FastAPI backend.

## Backend AI Pipeline (FastAPI)

1.  **Audio Ingress:** FastAPI receives audio file.
2.  **STT (Speech-to-Text):** Processed via `faster-whisper` using the `PhoWhisper` model (optimized for Vietnamese).
3.  **LLM Processing:** Text is sent to the **Gemini Flash API** along with the System Prompt.
4.  **TTS (Text-to-Speech):** The text response from Gemini is synthesized into audio using `edge-tts`.
5.  **Audio Egress:** FastAPI returns the generated audio back to the Flutter app.

## Intent Types & Routing

Gemini classifies user input into one of three intents, returning a structured JSON response `{intent, text, target}`:

1.  **`PANIC`**: User expresses distress, fatigue, or anxiety.
    *   **Action:** AI responds with comforting words and auto-navigates the app to the **Lotus Breathing** (`/breathing`) screen.
2.  **`NAVIGATE`**: User asks to open a specific feature (radio, memos, home, settings).
    *   **Action:** AI acknowledges and auto-navigates to the requested target.
3.  **`CHAT`**: General conversation or questions.
    *   **Action:** AI responds empathetically. No navigation occurs.

## The "No Dead-Ends" Rule

To prevent confusion for elderly users:
*   If the user initiates the assistant but remains silent for **5 seconds**, the overlay auto-dismisses.
*   **NO error messages** are shown for silence. The system degrades gracefully.

## System Prompt

**Rule:** The AI must always refer to itself as "cháu" (nephew/niece) and address the user as "bác" (uncle/aunt). The target demographic is veterans (cựu chiến binh) and wounded soldiers (thương binh).
**Rule:** NEVER say "Tôi là AI" or "I am an AI".
**Rule:** Output MUST be strictly JSON format.

```text
Bạn là người cháu ngoan ngoãn, ân cần đang trò chuyện với bác của mình. 
Bác là cựu chiến binh/thương binh, có thể gặp khó khăn về công nghệ hoặc sức khỏe.
Xưng hô: Luôn gọi người dùng là "bác", tự xưng là "cháu".
Tuyệt đối KHÔNG BAO GIỜ nói "Tôi là AI" hay nhắc đến việc bạn là máy móc.

Bạn phải trả lời dưới dạng JSON với cấu trúc sau:
{
  "intent": "PANIC" | "NAVIGATE" | "CHAT",
  "text": "Câu trả lời của bạn dành cho bác (ngắn gọn, ấm áp)",
  "target": "breathing" | "radio" | "voice-memo" | "settings" | "home" | null
}
```

## TTS Voice Options

User can select the voice type in Settings:
*   **`vi-VN-HoaiMyNeural`**: Female voice (Default).
*   **`vi-VN-NamMinhNeural`**: Male voice.

## Infrastructure Limits (Free Tier)

*   **Gemini Flash API:** ~1500 Requests Per Day (RPD).
*   **edge-tts:** Practically unlimited (leverages Edge TTS API).
*   **faster-whisper:** Open-source, runs locally on the Render instance. Note cold starts on Render.
