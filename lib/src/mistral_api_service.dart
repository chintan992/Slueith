import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Identifies a movie from a base64-encoded JPEG image using Mistral AI's API.
/// Returns the movie title or an error message prefixed with "Error:".
Future<String> identifyMovieFromImage(String base64Image) async {
  const endpoint = 'https://api.mistral.ai/v1/chat/completions';
  const apiKey = 'sVXVIyRLwiv7tiLlVrROinxoEfPnXzG9';
  const prompt = '''
Please analyze this movie poster or still frame and identify the movie title.
If you can identify the movie with high confidence, respond with just the title.
If you're not sure, respond with "Unknown".
Avoid explaining or describing what you see - just return the title or "Unknown".
''';

  final headers = {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  final body = jsonEncode({
    'model': 'mistral-small-latest',
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': prompt,
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            },
          },
        ],
      },
    ],
  });

  try {
    final response = await http
        .post(Uri.parse(endpoint), headers: headers, body: body)
        .timeout(const Duration(seconds: 30));

    switch (response.statusCode) {
      case 200:
        final jsonResponse = jsonDecode(response.body);
        final content = jsonResponse['choices'][0]['message']['content'] as String;
        return content.trim();

      case 400:
      case 422:
        return 'Error: The selected model does not support image input. Please contact support for assistance.';
        
      case 401:
        return 'Error: Invalid or expired API key. Please check your credentials.';
        
      case 429:
        return 'Error: Rate limit exceeded. Please try again in a few minutes.';
        
      case >= 500:
        return 'Error: The AI service is temporarily unavailable. Please try again later.';
        
      default:
        return 'Error: Unexpected response (${response.statusCode}). Please try again.';
    }
  } on TimeoutException {
    return 'Error: Request timed out. Please check your connection and try again.';
  } on SocketException {
    return 'Error: Network connection failed. Please check your internet connection.';
  } on FormatException {
    return 'Error: Invalid response from server. Please try again.';
  } catch (e) {
    return 'Error: ${e.toString()}';
  }
}