class AiMessage {
  AiMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  final AiMessageRole role;
  final String text;
  final DateTime timestamp;
  final bool isStreaming;
}

enum AiMessageRole { user, assistant }
