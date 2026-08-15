# State Management in LotusHaven

LotusHaven uses **Riverpod** (`flutter_riverpod`) as the primary state management solution, replacing Provider for better compile-time safety and dependency injection capabilities.

## Key Providers

The application state is divided into logical domains handled by specific providers:

*   `authProvider`: Manages user authentication state (logged in, logged out, loading, error).
*   `conversationProvider`: Manages the state of the active chat and chat history.
*   `settingsProvider`: Manages user preferences (theme, voice type, accessibility settings).
*   `assistantProvider`: Manages the state of the Voice Assistant overlay (idle, listening, processing, speaking).
*   `radioProvider`: Manages the radio player state (current station, playing, paused, buffering).

## Pattern: StateNotifier + AsyncValue

For managing asynchronous state (like fetching data from Supabase), we utilize the `StateNotifierProvider` or the newer `@riverpod` code generation with `AsyncValue`.

`AsyncValue` provides a safe way to handle three distinct states of an asynchronous operation:
1.  `AsyncData`: Data loaded successfully.
2.  `AsyncLoading`: Data is currently being fetched.
3.  `AsyncError`: An error occurred during fetching.

## Connecting Providers to Supabase Realtime

Riverpod integrates seamlessly with Supabase Realtime streams using `StreamProvider`.

## Example Code Snippets

### 1. Basic Provider for User Settings

```dart
// domain/models/user_settings.dart
class UserSettings {
  final bool soundEnabled;
  final String voiceType;
  // ... constructor and copyWith
}

// presentation/providers/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsNotifier extends StateNotifier<AsyncValue<UserSettings>> {
  SettingsNotifier() : super(const AsyncValue.loading()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Fetch from Supabase
      // final settings = await supabase.from('user_settings')...
      // state = AsyncValue.data(settings);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AsyncValue<UserSettings>>((ref) {
  return SettingsNotifier();
});
```

### 2. StreamProvider for Realtime Data (e.g., Messages)

```dart
// presentation/providers/conversation_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messagesStreamProvider = StreamProvider.family<List<Message>, String>((ref, conversationId) {
  final supabase = ref.watch(supabaseClientProvider);
  return supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at', ascending: true)
      .map((maps) => maps.map((m) => Message.fromJson(m)).toList());
});
```

### 3. Using AsyncValue in the UI

```dart
// presentation/screens/conversation_screen.dart
Widget build(BuildContext context, WidgetRef ref) {
  final messagesAsync = ref.watch(messagesStreamProvider(widget.conversationId));

  return messagesAsync.when(
    data: (messages) => ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, index) => ChatBubble(message: messages[index]),
    ),
    loading: () => const CircularProgressIndicator(),
    error: (error, stack) => Text('Lỗi: $error'), // Error state
  );
}
```
