import 'dart:convert';



import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;



import 'package:flutter_seguridad_en_casa/core/config/environment.dart';

import 'package:flutter_seguridad_en_casa/features/ai/domain/ai_message.dart';



class AiAssistantService {

  AiAssistantService({http.Client? client}) : _client = client ?? http.Client();



  final http.Client _client;



  static const _model =

      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';



  Future<String> generateReply(List<AiMessage> history) async {
    final apiKey = Environment.geminiApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return 'ai.error.missingKey'.tr;
    }

    final trimmedHistory = history.length > 12
        ? history.sublist(history.length - 12)
        : history;

    try {
      final uri = Uri.parse('$_model?key=$apiKey');
      final payload = {
        'systemInstruction': {
          'parts': [
            {'text': 'ai.systemPrompt'.tr},
          ],
        },
        'contents': trimmedHistory
            .map(
              (message) => {
                'role': message.role == AiMessageRole.user ? 'user' : 'model',
                'parts': [
                  {'text': message.text},
                ],
              },
            )
            .toList(),
      };

      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = body['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final first = candidates.first as Map<String, dynamic>;
          final content = first['content'] as Map<String, dynamic>?;
          final parts = content?['parts'];
          if (parts is List && parts.isNotEmpty) {
            final firstPart = parts.first as Map<String, dynamic>;
            final text = firstPart['text'];
            if (text is String && text.trim().isNotEmpty) {
              return text.trim();
            }
          }
        }
        return 'ai.error.noResponse'.tr;
      }

      debugPrint('Gemini error (${response.statusCode}): ${response.body}');
      return 'ai.error.http'.trParams({'code': '${response.statusCode}'});
    } catch (e, st) {
      debugPrint('Gemini exception: $e\n$st');
      return 'ai.error.exception'.tr;
    }
  }
}


