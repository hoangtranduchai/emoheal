# State Management & Data Architecture in EmoHeal

EmoHeal employs a **Clean Architecture & Local-First Service Pattern** optimized for low battery usage, high FPS performance, and seamless offline resilience on Android and iOS.

## Core Architectural Layers

1.  **Presentation Layer (`lib/presentation/`)**:
    *   Responsive Screen Widgets (`StatefulWidget`) managing local UI lifecycles.
    *   `LiveVoiceOverlay`: Reactive full-duplex voice overlay with dynamic lotus waveform animation and live subtitles ($\ge 18\text{sp}$).
    *   `AssistantBubble`: Persistent voice bubble triggering real-time Gemini Live sessions on single tap.

2.  **Service & Data Layer (`lib/data/`)**:
    *   `LiveVoiceService`: Real-time WebSocket manager for Gemini Live API. Handles 16kHz PCM mic streaming, 24kHz native audio playback, Barge-in (< 50ms), Hybrid VAD (`audio_stream_end`), Session Resumption, and Live Subtitle streams.
    *   `SupabaseService`: Offline-first database service with automatic fallback to `SharedPreferences`. Handles local emergency contacts, voice memos, user settings, and cloud sync upon authentication.
    *   `ApiService`: HTTP REST client & WebSocket URL resolver.

3.  **Core Utilities (`lib/core/`)**:
    *   `SoundCoordinator`: Central audio arbiter managing priorities between Background Radio, Screen Guides, and Live Assistant Voice.
    *   `VoiceGuide`: Centralized audio guidance player with token-based screen cancellation.
    *   `AppLogger`: Structured logging for network, database, navigation, and phone error tracking.
    *   `ResponsiveUtils`: Device breakpoint detection (Mobile $\le 768$dp, Tablet $> 768$dp).

## Session State & Privacy (Option A - Ephemeral Mode)

*   **Zero-Persistence Chat:** AI conversations exist strictly in active RAM state. When the user exits the chat or live overlay, memory is immediately released.
*   **Local-First Cache:** Settings and emergency contacts persist across app launches using `SharedPreferences`, avoiding unnecessary network latency.
