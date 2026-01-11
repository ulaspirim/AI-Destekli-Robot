import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

const String VERTEX_PROJECT_ID = 'flutterprojem-482419';
const String VERTEX_LOCATION = 'europe-west1';
const String VERTEX_MODEL = 'gemini-2.5-flash'; 

class GeminiService {
  auth.AutoRefreshingAuthClient? _client;
  List<Map<String, dynamic>> _chatHistory = [];

  Future<void> initialize(AssetBundle assetBundle) async {
    try {
      final serviceAccountJson = await assetBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> serviceAccount = jsonDecode(serviceAccountJson);
      final credentials = auth.ServiceAccountCredentials.fromJson(serviceAccount);
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      _client = await auth.clientViaServiceAccount(credentials, scopes);
      print("✅ Vertex AI servisi başlatıldı.");
    } catch (e) {
      print("❌ Vertex AI başlatma hatası: $e");
    }
  }

  void resetContext() {
    _chatHistory.clear();
  }

  // Context Injection (Bina bilgisini her mesajda hatırlatmak yerine geçmişe ekleyebiliriz)
  void setSystemContext(String context) {
    if (_chatHistory.isEmpty) {
      _chatHistory.add({
        "role": "user",
        "parts": [{"text": "Sistem Bilgisi: $context"}]
      });
      _chatHistory.add({
        "role": "model",
        "parts": [{"text": "Anlaşıldı. Bu bilgilere göre davranacağım."}]
      });
    }
  }

  Future<String> generateContent({
    required String prompt,
    String? imageBase64,
  }) async {
    if (_client == null) return "Servis başlatılmadı.";

    final url = Uri.parse(
      'https://$VERTEX_LOCATION-aiplatform.googleapis.com/v1/projects/$VERTEX_PROJECT_ID/locations/$VERTEX_LOCATION/publishers/google/models/$VERTEX_MODEL:generateContent',
    );

    final Map<String, dynamic> textPart = {"text": prompt};
    final List<Map<String, dynamic>> parts = [textPart];

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      parts.add({
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": imageBase64,
        }
      });
    }

    // Resimsiz sohbette geçmişi kullan
    if (imageBase64 == null) {
       _chatHistory.add({
        "role": "user",
        "parts": [{"text": prompt}]
      });
    }

    List<Map<String, dynamic>> contentsToSend;
    if (imageBase64 != null) {
       contentsToSend = [
         {
           "role": "user",
           "parts": parts
         }
       ];
    } else {
       contentsToSend = List.from(_chatHistory);
    }

    final Map<String, dynamic> requestBody = {
      "contents": contentsToSend,
      "generationConfig": {
        "temperature": 0.7, 
        "topP": 0.9,
        "maxOutputTokens": 2000, // ARTTIRILDI: Cevap yarıda kesilmesin diye
      }
    };

    try {
      final response = await _client!.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.containsKey('candidates') && (data['candidates'] as List).isNotEmpty) {
           String reply = data['candidates'][0]['content']['parts'][0]['text'] ?? "Boş yanıt";
           
           if (imageBase64 == null) {
             _chatHistory.add({
               "role": "model",
               "parts": [{"text": reply}]
             });
           }
           return reply;
        }
        return "Yanıt alınamadı.";
      } else {
        return "API Hatası: ${response.statusCode}";
      }
    } catch (e) {
      return "Bağlantı hatası: $e";
    }
  }
  
  void dispose() {
    _client?.close();
  }
}