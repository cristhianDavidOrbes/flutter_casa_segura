import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:flutter_seguridad_en_casa/features/ai/data/security_chat_store.dart';
import 'package:flutter_seguridad_en_casa/features/ai/domain/security_chat_message.dart';

class SecurityChatHistoryPage extends StatelessWidget {
  const SecurityChatHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conversaciones')),
      body: ValueListenableBuilder<Box<SecurityChatMessage>>(
        valueListenable: SecurityChatStore.listenable(),
        builder: (context, box, _) {
          final messages = box.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          if (messages.isEmpty) {
            return Center(
              child: Text(
                'Sin conversaciones almacenadas.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final isUser = message.role == 'user';
              final alignment = isUser
                  ? Alignment.centerRight
                  : Alignment.centerLeft;
              final bgColor = isUser
                  ? cs.primary
                  : cs.surfaceContainerHighest.withValues(alpha: 0.9);
              final fgColor = isUser ? cs.onPrimary : cs.onSurface;
              return Align(
                alignment: alignment,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message.text, style: TextStyle(color: fgColor)),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(message.createdAt),
                        style: TextStyle(
                          color: fgColor.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
