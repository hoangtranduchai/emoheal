# CLAUDE.md — EmoHeal ("Vòng tay thấu cảm")

## 1. Project Overview

**EmoHeal** ("Vòng tay thấu cảm") is a cross-platform Flutter app providing mental health support for Vietnamese war veterans and elderly users through **Speech Emotion Recognition (SER)** and empathetic AI companionship. It features real-time acoustic prosody & semantic emotion analysis (6 states), guided lotus breathing, nostalgic radio, and voice memoir recording. The core UX principle is **Zero-Barrier**: all interactions are designed for users with limited tech literacy, trembling hands, and low vision.

## 2. Tech Stack

| Layer | Technology | Version / Model |
|---|---|---|
| Frontend | Flutter (Dart) | SDK ≥3.3.0 |
| Navigation | AppRouter (Fade Transitions) | Clean Architecture |
| Local Storage | SharedPreferences (Offline-first) | ^2.3.2 |
| Database & Cloud | Supabase (PostgreSQL 15) | supabase_flutter ^2.17.1 |
| Backend API | Python FastAPI | 0.115.0 |
| Real-Time Voice AI | Gemini Live API (Native Audio) | `gemini-3.1-flash-live-preview` |
| Text & Audio AI | Google GenAI SDK (Multimodal SER) | `gemini-3.7-flash` / `gemini-3.5-flash-lite` |
| TTS | edge-tts (MD5 Memory Cache) | 6.1.12 (`vi-VN-HoaiMyNeural` & `vi-VN-NamMinhNeural`) |

## 3. Dev Commands

```bash
# Flutter (Frontend)
flutter pub get                  # Install dependencies / Cài dependencies
dart analyze lib                 # Lint check / Kiểm tra lint
flutter test                     # Run widget tests / Chạy unit/widget test
flutter run -d chrome            # Run web dev / Chạy trên web
flutter run                      # Run on connected device / Chạy trên thiết bị

# Backend (Python)
cd backend
pip install -r requirements.txt  # Install backend deps / Cài deps backend
pytest test_main.py              # Run backend tests / Chạy test backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000  # Run dev server

# Git (GitHub Flow — NEVER commit to main directly)
git checkout -b feature/your-feature  # Create feature branch
git checkout -b bug/your-bugfix       # Create bug branch
```

## 4. Core Logic Summary

- **Speech Emotion Recognition (SER) & Voice AI**: Multi-tier SER analyzing acoustic prosody (pitch, energy, tempo, tremor) + semantic sentiment to classify 6 emotion states: `PANIC_STRESS`, `SADNESS`, `NOSTALGIA`, `CALM`, `HAPPINESS`, `NEUTRAL`. Two modes: (1) Bidirectional WebSocket `/ws/live-assistant` powered by `gemini-3.1-flash-live-preview` with VAD, Barge-in, and Function Calling; (2) REST API `/api/assistant` powered directly by `gemini-3.7-flash` Multimodal Audio (no Whisper/PyTorch server dependency) + Edge-TTS. See [AI Architecture](.claude/docs/ai_architecture.md).
- **Auth & Zero Barrier**: Instant Guest Mode with offline-first local storage (`SharedPreferences`). Phone authentication via 4-digit OTP ($0 Budget). Auto-syncs local data to cloud on login.
- **Privacy & Conversation**: Option A (Session-based / Ephemeral chat in RAM). Conversations exist only during active screen session to protect privacy.
- **Responsive**: All 10 mobile screens responsive to tablet (768px+). Use `ResponsiveUtils.isTablet(context)`.


## 5. Key Constraints

> **DO NOT** change or assume any of these without explicit user approval:

1. **Budget = $0**. All services must use free tiers only.
2. **No "Góc bình yên" or "ChatScreen"**. Removed from scope (conversations unified in "Hồi ký Giọng nói" and "Bạn đồng hành" live voice).
3. **No Community Forum**. Cut from MVP.
4. **Vietnamese only**. All UI text, error messages, TTS use Vietnamese. Comments bilingual (EN + VI).
5. **Touch targets ≥ 48dp**. Non-negotiable for elderly accessibility.
6. **Font minimum 16sp**. Smallest text in entire app.
7. **System Prompt**: AI xưng "cháu", gọi user "bác". Never say "Tôi là AI". App serves cựu chiến binh & thương binh (NOT liệt sĩ — they are deceased).
8. **SOS Button**: 3-second hold → call 115 OR call family member.
9. **Color palette from Figma**: `#F7F5F0` (bg), `#3C7232` (primary), `#26591D` (header), `#D97750` (SOS).
10. **Secrets**: NEVER commit `.env` files. Use `.env.example` for templates.
11. **Branch Management**: Before adding any features or fix bugs, always work on a new git branch. Never commit directly on main. Bug branches must follow naming convention bug/[des], feature branches follow naming convention feature/[desc].

## 6. Additional Documentation

| Document | Path | Contents |
|---|---|---|
| Architecture | [.claude/docs/architecture.md](.claude/docs/architecture.md) | System architecture, data flow, deployment |
| State Management | [.claude/docs/state_management.md](.claude/docs/state_management.md) | Riverpod providers, state patterns |
| Database Schema | [.claude/docs/database_schema.md](.claude/docs/database_schema.md) | Tables, RLS, Custom Claims, migrations |
| AI Architecture | [.claude/docs/ai_architecture.md](.claude/docs/ai_architecture.md) | STT/TTS/LLM flow, System Prompt, intents |
| UI Components | [.claude/docs/ui_components.md](.claude/docs/ui_components.md) | Shared widgets, Figma node mappings |
| Git Workflow | [.claude/docs/git_workflow.md](.claude/docs/git_workflow.md) | GitHub Flow, branch naming, PR process |
| Screens Map | [.claude/docs/screens_map.md](.claude/docs/screens_map.md) | All 11 screens with Figma node IDs |

## 7. Code Style

- **Comments**: Bilingual EN + VI. Brief. Explain *why*, not *what*.
- **No dead code**: Remove unused imports, widgets, files.
- **Theme only**: Use `AppColors.*` and `AppTheme.*`. No hardcoded hex values.
- **Read this file + relevant `.claude/docs/` files before making changes.**
