# Screens Map & Navigation

EmoHeal consists of 9 core mobile screens (10 total with Onboarding) connected via `AppRouter` with smooth Fade Transitions and zero dead-ends, augmented with the persistent "Bạn đồng hành" (Live Voice) system.

*(Note: "Góc bình yên", "Community Forum", and "ChatScreen" were removed from scope to simplify interactions for elderly users).*

## Screen Inventory

| # | Screen | Route Constant | Path | Status | Purpose |
|---|---|---|---|---|---|
| 1 | Onboarding | `AppRoutes.onboarding` | `/` | Active | Video background, welcome audio guide |
| 2 | Auth Login | `AppRoutes.authLogin` | `/auth/login` | Active | 56dp phone input, skip-to-guest button |
| 3 | Auth OTP | `AppRoutes.authOtp` | `/auth/otp` | Active | 4-digit Pinput with audio prompt |
| 4 | Home | `AppRoutes.home` | `/home` | Active | TopHeader with Bác's name, 3s SOS, contacts, 4 cards, AssistantBubble |
| 5 | Hồi ký Giọng nói | `AppRoutes.voiceMemo` | `/voice_memos` | Active | Topic suggestions, pulse recorder, upload, emotion feedback |
| 6 | Danh sách Hồi ký | `AppRoutes.history` | `/history` | Active | Dedicated Voice Memoir player & transcripts |
| 7 | Nhịp thở Hoa Sen | `AppRoutes.lotusBreathing` | `/lotus_breathing` | Active | 4-4-6 breathing rhythm with video/petal animation |
| 8 | Đài Radio | `AppRoutes.radio` | `/radio` | Active | Nostalgic folk, poetry, revolution songs |
| 9 | Cài đặt & Trợ năng | `AppRoutes.settings` | `/settings` | Active | Name edit, font scaler, anti-mis-tap, voice picker |

## Design & Accessibility Guidelines

*   **Zero-Barrier Principle:** Minimum 48dp touch targets, minimum 16sp text.
*   **Persistent Global "Bạn đồng hành" Bubble:** Draggable overlay button appearing across all screens in the app with edge-snapping, direct two-way speech, and spoken voice tool navigation via Gemini Live API.
*   **SOS Safety:** 3-second continuous hold with haptic feedback to prevent accidental triggers.
*   **Responsive:** All screens adapt smoothly to tablet viewports (768px+) via `ResponsiveUtils`.
