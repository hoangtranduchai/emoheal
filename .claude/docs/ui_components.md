# UI Components & Design System

The LotusHaven app follows a specific design system tailored for accessibility, especially for elderly users. 

**Figma Reference:** `CzfLAPE2JITOhRM3HdrBbe`

## Design System Core (`lib/core/theme.dart`)

### Colors (`AppColors`)

The palette is designed to be calming, high-contrast, and clear.

*   `backgroundLight`: `#F7F5F0` (Soft cream/off-white)
*   `primaryGreen`: `#3C7232` (Lotus leaf green - Primary brand color)
*   `primaryGreenDark`: `#26591D` (Darker green for contrast elements)
*   `sosOrange`: `#D97750` (Warm orange for emergency actions)
*   `textOnDark`: `#F9FBEB` (Light text on dark backgrounds)
*   `textPrimary`: `#111111` (High contrast text for readability)

### Typography

*   **Font Family:** Google Fonts **Roboto**. Chosen for clarity and full support of Vietnamese diacritics.
*   **Minimum Font Size:** `16sp` to ensure readability for the elderly.

### Accessibility Standards

*   **Touch Targets:** Minimum `48dp` x `48dp` for all interactive elements.
*   **Inputs:** Form fields and primary buttons use `56dp` heights.

## Shared Widgets

Reusable components built to maintain consistency across the app.

1.  **`AssistantBubble`**: The 64x64 FAB utilizing `support.gif`. Appears on all screens via a persistent shell route.
2.  **`SOSButton`**: A critical UI component. Features a 3-layer ripple effect. Requires a **3-second hold** to activate (calls 115 or family) to prevent accidental triggers.
3.  **`FeatureCard`**: Used on the Home screen for primary navigation (Hồi ký, Nhịp thở, Radio, Cài đặt). Large touch area.
4.  **`ChatHistoryItem`**: A shared list item component for previous conversations.
5.  **`TopicSuggestionCard`**: A grid of 6 cards used in the Voice Memo screen to prompt memories.
6.  **`RecordingControls`**: A complex stateful widget managing 7 states: idle, recording, paused, playing, stopped, loading, error.
7.  **`RadioPlayerBar`**: Persistent or inline bar showing play/pause, progress, and current track metadata.
8.  **`AppButton`**: The unified button component, enforcing the `56dp` height standard, heavily used in Auth screens.

## Responsive Design

The application must be fully responsive across devices.

*   **Mobile:** Base layout designed for `375px` width.
*   **Tablet:** Layouts adapt for screens `768px+`. (Figma provides tablet references for Home and Radio screens).

### `ResponsiveUtils`

A helper class (e.g., `lib/utils/responsive_utils.dart`) should be used to manage breakpoints:

```dart
class ResponsiveUtils {
  static const double tabletBreakpoint = 768.0;

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }
  
  static double scaleFactor(BuildContext context) {
    // Logic to scale text/padding based on screen size
  }
}
```
