import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_seguridad_en_casa/core/config/environment.dart';



class GeminiVisionService {

  GeminiVisionService._();



  static final GeminiVisionService instance = GeminiVisionService._();



  static const _model =

      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';



  Future<String?> describeImage(
    Uint8List bytes, {
    required String context,
  }) async {
    final apiKey = Environment.geminiApiKey;
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final uri = Uri.parse('$_model?key=$apiKey');
      final payload = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': context},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Encode(bytes),
                },
              },
            ],
          },
        ],
      };

      final response = await http.post(
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
      } else {
        debugPrint(
          'Gemini describe error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Gemini describe exception: $e');
    }

    return null;
  }

  Future<bool?> isSamePerson(
    Uint8List firstImage,
    Uint8List secondImage,
  ) async {
    final apiKey = Environment.geminiApiKey;
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final uri = Uri.parse('$_model?key=$apiKey');
      final payload = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'security.gemini.compare.prompt'.tr,
              },
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Encode(firstImage),
                },
              },
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Encode(secondImage),
                },
              },
            ],
          },
        ],
      };

      final response = await http.post(
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
            final part = parts.first as Map<String, dynamic>;
            final raw = (part['text'] as String?)?.trim().toUpperCase();
            if (raw != null) {
              if (raw.contains('NO_MATCH') || raw.contains('NO MATCH')) {
                return false;
              }
              if (raw.contains('MATCH')) return true;
            }
          }
        }
      } else {
        debugPrint(
          'Gemini compare error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e, st) {
      debugPrint('Gemini compare exception: $e\n$st');
    }

    return null;
  }
}
