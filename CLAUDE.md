# CLAUDE.md — LotusHaven "Điểm Tựa"

## 1. Project Overview

LotusHaven is a cross-platform Flutter app providing mental health support for Vietnamese war veterans and elderly users. It features voice-first AI companionship, guided breathing (Lotus Breath), nostalgic radio, and voice memoir recording. The core UX principle is **Zero-Barrier**: all interactions are designed for users with limited tech literacy, trembling hands, and low vision.

## 2. Tech Stack

| Layer | Technology | Version |
|---|---|---|
| Frontend | Flutter (Dart) | SDK ≥3.3.0 |
| State | flutter_riverpod | ^2.6.1 |
| Routing | go_router | ^14.8.1 |
| Database & Auth | Supabase (PostgreSQL) | supabase_flutter ^2.17.1 |
| Backend API | Python FastAPI | 0.115.0 |
| AI/LLM | Google Gemini Flash | google-generativeai 0.8.0 |
| STT | faster-whisper (PhoWhisper) | 1.1.0 |
| TTS | edge-tts (vi-VN-HoaiMyNeural) | 6.1.12 |

## 3. Dev Commands

```bash
# Flutter (Frontend)
flutter pub get                  # Install dependencies / Cài dependencies
flutter analyze --no-fatal-infos # Lint check / Kiểm tra lint
flutter run -d chrome            # Run web dev / Chạy trên web
flutter run                      # Run on connected device / Chạy trên thiết bị

# Backend (Python)
cd backend
pip install -r requirements.txt  # Install backend deps / Cài deps backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000  # Run dev server

# Git (GitHub Flow — NEVER commit to main directly)
git checkout -b feature/your-feature  # Create feature branch
git checkout -b bug/your-bugfix       # Create bug branch
```

## 4. Core Logic Summary

- **AI Assistant**: Voice-first overlay. Records audio → STT (faster-whisper) → Gemini Flash classifies intent (PANIC/NAVIGATE/CHAT) → generates empathetic response → TTS (edge-tts) → plays audio. See [AI Architecture](.claude/docs/ai_architecture.md).
- **Auth**: Email/Password (priority 1), Magic Link (priority 2), Google Sign-In (priority 3). Custom Access Token Hook injects `user_role` into JWT for O(1) RLS checks.
- **Responsive**: All 11 mobile screens must responsive to tablet (768px+). Use `ResponsiveUtils.isTablet(context)`.

## 5. Key Constraints

> **DO NOT** change or assume any of these without explicit user approval:

1. **Budget = $0**. All services must use free tiers only.
2. **No "Góc bình yên" screen**. It was removed from scope.
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
