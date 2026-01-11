// GEREKLİ IMPORTLARI KONTROL ET
import '../core/robot_controller.dart'; 
import '../core/robot_state.dart'; // <--- 1. RobotState için bu import şart (dosya yolu projene göre değişebilir)
import 'vision_service.dart';
import 'voice_service.dart';
import 'gemini_service.dart';
import 'face_service.dart';

class InteractionManager {
  final RobotController robotController;
  final VisionService vision;
  final VoiceService voice;
  final GeminiService gemini;
  final FaceService faceService;

  InteractionManager({
    required this.robotController,
    required this.vision,
    required this.voice,
    required this.gemini,
    required this.faceService,
  });

  Future<void> onHumanDetected({required List<double> faceEmbedding}) async {
    // 1. Durumu güncelle
    robotController.setState(RobotState.humanDetected); 
    
    // Yüzü tanı
    final userId = await faceService.recognizeFace(faceEmbedding);

    // Eğer Gemini servisinde resetContext yoksa bu satırı silebilirsin
    // gemini.resetContext(); 

    if (userId != null) {
      await voice.speak("Merhaba $userId, tekrar hoş geldin.");
    } else {
      await voice.speak("Merhaba, seni daha önce görmemiştim. Adın nedir?");
    }

    // Sohbete başla
    robotController.setState(RobotState.chatting);
    _startConversationStep(); 
  }

  void _startConversationStep() {
    // Robot 'Chatting' modundan çıktıysa dur.
    if (robotController.currentState != RobotState.chatting) return;

    // 2. Dinlemeye başla (Düzeltme: 'listenOnce' yerine 'listen')
    voice.listen( 
      onResult: (text) async {
        if (text.isEmpty) {
           // Ses duyulmadıysa tekrar dinle veya bitir
           return;
        }

        // Kullanıcı "Güle güle" dediyse sohbeti bitir
        if (text.toLowerCase().contains("güle güle")) {
           await voice.speak("Görüşmek üzere.");
           robotController.setState(RobotState.exploring); // Veya idle
           return;
        }

        // 3. LLM'e sor (Düzeltme: 'ask' yerine 'generateContent')
        final response = await gemini.generateContent(prompt: text); 

        // 4. Cevabı seslendir
        await voice.speak(response);

        // 5. Cevap bitti, tekrar dinlemeye geç
        _startConversationStep(); 
      },
    );
  }
}