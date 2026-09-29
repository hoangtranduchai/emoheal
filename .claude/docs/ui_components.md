# UI Components & Design System

The EmoHeal app follows a specific design system tailored for accessibility, especially for elderly users. 

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

1.  **`AssistantBubble`**: The 64x64 global button with `support.gif` and "Bạn đồng hành" badge. Provides instant two-way voice interaction and app voice control via Gemini Live API.
2.  **`SOSButton`**: Critical emergency component. Features 3-second hold countdown, haptic vibrations, Priority 1 emergency contact lookup, and 115 auto-dialer fallback.
3.  **`FeatureCard`**: Used on the Home screen for primary navigation (Hồi ký, Nhịp thở, Radio, Cài đặt) with large touch targets.
4.  **`EmergencyContactChip`**: Compact horizontal chip for displaying and managing quick-dial emergency contacts on the Home screen.
5.  **`AddContactBottomSheet`**: Accessible modal sheet for adding emergency contacts (name and phone) with clear input fields.
6.  **`BreathingLotus`**: Smooth lotus flower blooming animation and video playback synced with 4-4-6 breathing cycles, featuring high-contrast white animated guidance subtitles ("Bác hãy hít vào", "Bác nín thở một chút nhé", "Bác hãy từ từ thở ra") positioned elegantly at the bottom with drop shadows and smooth transitions.


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
