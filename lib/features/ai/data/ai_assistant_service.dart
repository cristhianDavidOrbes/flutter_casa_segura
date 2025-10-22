import 'dart:convert';

import 'package:flutter/foundation.dart';
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
      return 'Parece que aún no configuraste tu clave de Gemini. Agrega GEMINI_API_KEY al archivo .env para habilitar las respuestas inteligentes.';
    }

    try {
      final uri = Uri.parse('$_model?key=$apiKey');
      final payload = {
        'contents': history
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
        return 'No recibí una respuesta útil del modelo en este momento. ¿Intentamos otra pregunta?';
      }

      debugPrint('Gemini error (${response.statusCode}): ${response.body}');
      return 'Hubo un problema al contactar al modelo (código ${response.statusCode}). Intenta de nuevo más tarde.';
    } catch (e, st) {
      debugPrint('Gemini exception: $e\n$st');
      return 'No pude comunicarme con el modelo en este momento. Revisa tu conexión e inténtalo otra vez.';
    }
  }
}
