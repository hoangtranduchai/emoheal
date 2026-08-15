import 'package:flutter/material.dart';
import '../../core/theme.dart';

class AssistantBubble extends StatelessWidget {
  final VoidCallback onTap;

  const AssistantBubble({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: FloatingActionButton(
        onPressed: onTap,
        backgroundColor: AppColors.assistantBubble,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
        child: const Text(
          '🤖',
          style: TextStyle(fontSize: 32),
        ),
      ),
    );
  }
}
