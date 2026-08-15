# Screens Map & Navigation

LotusHaven consists of 11 distinct mobile screens. The app uses `go_router` for navigation, specifically leveraging a `ShellRoute` to ensure the AI Assistant FAB is persistent across the app.

*(Note: The "Góc bình yên" screen has been removed from the requirements).*

## Screen Inventory

| # | Screen | Figma Node | Route | Status | Notes |
|---|---|---|---|---|---|
| 1 | Onboarding | `421:1221` | `/onboarding` | Exists | Needs bug fix |
| 2 | Auth Welcome | N/A (self-design) | `/auth` | New | |
| 3 | Auth Login | N/A (self-design) | `/auth/login` | New | |
| 4 | Auth OTP | N/A (self-design) | `/auth/otp` | New | |
| 5 | Home | `421:1289` (mobile) / `2693:300` (tablet) | `/` | Exists | Needs refactor |
| 6 | Hồi ký Giọng nói | `421:1845` | `/voice-memo` | Exists | Needs refactor |
| 7 | Hội thoại (Chat) | `2717:587` | `/conversation/:id` | New | |
| 8 | Lịch sử Hội thoại | `2490:528` | `/history` | Exists | Needs refactor |
| 9 | Nhịp thở Hoa Sen | `2550:186` / `2575:473` / `2575:596` | `/breathing` | Exists | Needs refactor |
| 10 | Đài Radio | `2585:403` / `2589:535` | `/radio` | Exists | Needs refactor |
| 11 | Cài đặt | `2512:267` | `/settings` | Exists | Needs refactor |

## Design Guidelines by Section

### Auth Screens
*   **Philosophy:** "Zero-Barrier" design tailored for the elderly.
*   **Elements:** 
    *   Large `56dp` input fields.
    *   Minimum `48dp` touch targets.
    *   Call-to-Action (CTA) buttons must be bottom-anchored.

### Home Screen
*   Contains 4 primary feature cards:
    1.  Hồi ký Giọng nói (Voice Memos)
    2.  Nhịp thở Hoa Sen (Lotus Breathing)
    3.  Đài Radio (Radio)
    4.  Cài đặt (Settings)

### Responsive Design (Tablet)
*   **Requirement:** ALL 11 screens must be responsive and adapt gracefully to tablet sizes.
*   While Figma only provides explicit tablet designs for Home and Radio, the principles must be applied globally (e.g., constraining max-widths, adjusting grid columns, or utilizing split views where appropriate).

## Navigation Architecture (`go_router`)

A `ShellRoute` is employed to wrap the main application content, allowing persistent UI elements like the `AssistantBubble` to remain on screen during transitions.

```dart
// Example router setup concept
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/onboarding', ...),
    GoRoute(path: '/auth', ...),
    // ... other standalone routes
    
    ShellRoute(
      builder: (context, state, child) {
        return Scaffold(
          body: child,
          floatingActionButton: const AssistantBubble(),
        );
      },
      routes: [
        GoRoute(path: '/', ...),
        GoRoute(path: '/voice-memo', ...),
        GoRoute(path: '/radio', ...),
        // ... nested routes that show the FAB
      ],
    )
  ]
)
```
