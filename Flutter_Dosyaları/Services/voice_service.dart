import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  bool isSpeaking = false;
  bool _isSttAvailable = false; 

  Future<void> init() async {
    try {
      // 1. TTS Ayarları (Önce bunu yapalım)
      if (Platform.isIOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            ]
        );
      }
      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.awaitSpeakCompletion(true); // Konuşma bitmeden işlem yapma

      // 2. STT (Mikrofon) Başlatma
      _isSttAvailable = await _speechToText.initialize(
        onError: (val) => print('🔥 STT Hatası: ${val.errorMsg}'),
        onStatus: (val) => print('🎤 STT Durumu: $val'),
        debugLogging: true, // Hata ayıklamak için logları açtık
      );

      print("Voice Service Başlatıldı. Mikrofon durumu: $_isSttAvailable");

    } catch (e) {
      print("Voice Service Başlatma Hatası: $e");
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    // Konuşmaya başlamadan önce mikrofonu kesinlikle kapat
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
    
    isSpeaking = true;
    await _flutterTts.speak(text);
    isSpeaking = false;
  }

  Future<void> listen({required Function(String) onResult}) async {
    // Mikrofon yoksa çık
    if (!_isSttAvailable) {
      print("⚠️ Mikrofon başlatılamadığı için dinleme yapılamıyor.");
      // Tekrar init etmeyi dene
      await init(); 
      return;
    }

    // Eğer robot konuşuyorsa, önce sustur
    if (isSpeaking) {
      await _flutterTts.stop();
      isSpeaking = false;
    }

    // Zaten dinliyorsa tekrar başlatma
    if (_speechToText.isListening) return;

    try {
      print("🎤 Dinleme başlatılıyor...");
      await _speechToText.listen(
        localeId: 'tr_TR', 
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            print("✅ Algılandı: ${result.recognizedWords}");
            onResult(result.recognizedWords);
          }
        },
      );
    } catch (e) {
      print("❌ Dinleme hatası: $e");
    }
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
    isSpeaking = false;
  }

  void stopListening() {
    _speechToText.stop();
  }

  bool get isListening => _speechToText.isListening;
}