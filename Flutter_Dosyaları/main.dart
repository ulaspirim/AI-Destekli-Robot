import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; 
import 'package:image/image.dart' as img_lib;
import 'firebase_options.dart';
import 'services/gemini_service.dart';
import 'services/vision_service.dart';
import 'services/hardware_service.dart';
import 'services/voice_service.dart';
import 'services/face_service.dart';
import 'core/robot_state.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Kamera hatası: $e");
  }
  runApp(const AiTestApp());
}

class AiTestApp extends StatelessWidget {
  const AiTestApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Robot',
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const AiTestScreen(),
    );
  }
}

class AiTestScreen extends StatefulWidget {
  const AiTestScreen({super.key});
  @override
  State<AiTestScreen> createState() => _AiTestScreenState();
}

class _AiTestScreenState extends State<AiTestScreen> {
  // --- SERVİSLER ---
  final GeminiService _geminiService = GeminiService();
  final VisionService _visionService = VisionService();
  final HardwareService _hardwareService = HardwareService();
  final VoiceService _voiceService = VoiceService();
  final FaceService _faceService = FaceService(); // Yüz Tanıma Servisi
  
  late FaceDetector _faceDetector;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- ROBOT BİLGİSİ VE KONUM ---
  // Burası Gemini'ye robotun nerede olduğunu öğretir.
  final String _buildingContext = """
  Şu an Teknoloji Fakültesi Binası, 1. Kattasın.
  Bu katta: Bilgisayar Laboratuvarı, Elektronik Laboratuvarı ve Öğrenci Kantini var.
  Sen bu binanın asistan robotusun.
  Görevin: Devriye atmak ve gördüğün insanlara yardımcı olmak.
  """;

  // --- DURUM YÖNETİMİ ---
  RobotState _robotState = RobotState.idle;
  CameraController? _cameraController;
  
  String _statusMessage = "Sistem Hazırlanıyor...";
  String _geminiResponse = "";
  String _navigationLog = "Beklemede";
  
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;

  // State Flags
  bool _isPatrolMode = false;
  bool _isProcessing = false;
  bool _isChatting = false;
  bool _ignoreHumans = false; // Devriyeye dönerken insanları kısa süre görmezden gel

  Timer? _patrolLoopTimer;

  @override
  void initState() {
    super.initState();
    
    final options = FaceDetectorOptions(
      enableClassification: false,
      enableContours: false,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate, 
    );
    _faceDetector = FaceDetector(options: options);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAll();
    });
  }

  @override
  void dispose() {
    _faceDetector.close();
    _patrolLoopTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeAll() async {
    await _requestPermissions();
    
    if (mounted) {
    
      bool isGeminiReady = await _geminiService.initialize(DefaultAssetBundle.of(context));
      
      if (isGeminiReady) {
        _geminiService.setSystemContext(_buildingContext);
        setState(() => _statusMessage = "Yapay Zeka Hazır.");
      } else {
        setState(() => _statusMessage = "HATA: Gemini Başlatılamadı! (JSON Dosyasını Kontrol Et)");
        // Sesli uyarı ver ki hatayı duy
        await _voiceService.speak("Sistem hatası. Yapay zeka anahtarı bulunamadı.");
      }
    }
    
    _visionService.init();
    await _voiceService.init();
    _initBluetooth();
    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    var cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front, 
      orElse: () => cameras.first
    );

    _cameraController = CameraController(
      cam, 
      ResolutionPreset.medium, 
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  // ===========================================================================
  //       1. OTONOM DEVRİYE
  // ===========================================================================

  void _toggleAutonomousMode() {
    setState(() {
      if (_isPatrolMode) {
        // Durdur
        _isPatrolMode = false;
        _isProcessing = false;
        _patrolLoopTimer?.cancel();
        _sendCommandToArduino("DUR");
        _statusMessage = "Otonom mod kapalı.";
        _robotState = RobotState.idle;
      } else {
        // Başlat
        _isPatrolMode = true;
        _isChatting = false;
        _ignoreHumans = false; // Başlangıçta insanları gör
        _statusMessage = "Devriye Modu Aktif";
        _robotState = RobotState.searching;
        _startPatrolLoop();
      }
    });
  }

  void _startPatrolLoop() {
    _patrolLoopTimer?.cancel();
   
    _patrolLoopTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      
      if (!_isPatrolMode) { timer.cancel(); return; }
      if (_isChatting) { timer.cancel(); return; }
      if (_isProcessing) return; // Zaten işlem yapılıyorsa bekle
      
      // Kamera yoksa veya hata varsa dur
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
         _sendCommandToArduino("DUR");
         return;
      }

      _isProcessing = true;

      try {
        final imageFile = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(imageFile.path);

        // A. İnsan Kontrolü
        List<Face> faces = [];
        if (!_ignoreHumans) {
           faces = await _faceDetector.processImage(inputImage);
        }

        if (faces.isNotEmpty) {
          print("!!! İNSAN GÖRÜLDÜ !!!");
          timer.cancel(); 
          // Robot hemen durmalı
          _sendCommandToArduino("DUR"); 
          await _handleHumanEncounter(imageFile.path);
        } else {
          // B. Navigasyon
          await _handleNavigation(imageFile.path);
        }

      } catch (e) {
        
        print("KRİTİK HATA: $e");
        setState(() => _statusMessage = "Hata: Güvenli moda geçildi.");
        _sendCommandToArduino("DUR"); // Fiziksel olarak dur
        
        // Hatayı temizlemek için processing'i kapat
        _isProcessing = false;
      } finally {
        // Eğer sohbete girmediysek işlem bayrağını indir
        if (!_isChatting) _isProcessing = false;
      }
    });
  }

  // ===========================================================================
  //          2. NAVİGASYON
  // ===========================================================================

  Future<void> _handleNavigation(String imagePath) async {
    setState(() => _navigationLog = "Yol analizi yapılıyor...");

    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    String prompt = """
    Sen bir robotsun. Önünü analiz et.
    ÖNEMLİ: Eğer önün boşsa ve engel yoksa 'ILERI' de.
    Engel varsa 'SOL' veya 'SAG' tarafı seç. Çıkmaz sokaksa 'GERI' de.
    Cevap formatı tek kelime: ILERI, SOL, SAG, GERI, DUR.
    """;

    try {
      final response = await _geminiService.generateContent(
        prompt: prompt,
        imageBase64: base64Image,
      );

      print("Navigasyon Kararı: $response");

      String command = "dur";
      if (response.toUpperCase().contains("ILERI")) command = "ileri";
      else if (response.toUpperCase().contains("SOL")) command = "sol";
      else if (response.toUpperCase().contains("SAG")) command = "sag";
      else if (response.toUpperCase().contains("GERI")) command = "geri";

      // Hareket süresini duruma göre ayarla
      // İleri giderken 2 saniye, dönerken 1 saniye hareket et
      int durationMs = 0;
      
      if (command == "ileri" || command == "geri") {
        // Arduino kodunda süre: 1500 ms
        // Flutter bekleme süresi: 1600 ms (100ms güvenlik payı)
        durationMs = 1600; 
      } else if (command == "sol" || command == "sag") {
        // Arduino kodunda süre: 500 ms
        // Flutter bekleme süresi: 600 ms (100ms güvenlik payı)
        durationMs = 600;
      }
      
      _moveRobot(command, durationMs: durationMs);
    } catch (e) {
      print("Navigasyon Hatası: $e");
      _moveRobot("dur");
      // Eğer hata metninde 429 geçiyorsa
      if (e.toString().contains("429")) {
        print("KOTA AŞIMI! Robot 1 dakika dinleniyor...");
        _voiceService.speak("Çok yoruldum, sistemlerimi soğutuyorum.");
        
        // Geçici olarak devriyeyi durdur
        _patrolLoopTimer?.cancel();
        
        // 1 dakika sonra tekrar başlat
        Future.delayed(const Duration(minutes: 1), () {
          _startPatrolLoop();
        });
      } else {
        print("Hata oluştu: $e");
      }
    }
  }

  void _moveRobot(String command, {int durationMs = 600}) {
    setState(() => _navigationLog = "Hareket: ${command.toUpperCase()}");
    _sendCommandToArduino(command);
    
    if (command != "dur") {
      // Düzeltme: Hareket süresi uzatıldı ve timer çakışması önlendi
      Future.delayed(Duration(milliseconds: durationMs), () {
        // Eğer hala devriyedeysek ve sohbet etmiyorsak durdur.
        // Bu sayede robot engle çarpmaz.
        if (!_isChatting && _isPatrolMode) {
           // Hemen durdurmak yerine bir sonraki kararı beklemesi için
           // burayı yoruma alabilirsin ama güvenlik için durması iyidir.
           _sendCommandToArduino("dur");
        }
      });
    }
  }


  // ===========================================================================
  //         3. GÖRSEL HAFIZA VE SOHBET
  // ===========================================================================

  Future<void> _handleHumanEncounter(String imagePath) async {
    print("İnsan prosedürü başlatılıyor...");
    
    _patrolLoopTimer?.cancel();
    _patrolLoopTimer = null;
    _sendCommandToArduino("DUR"); // Hemen dur
    
    setState(() {
      _isChatting = true;
      _isPatrolMode = false;
      _isProcessing = false;
      _robotState = RobotState.humanDetected;
      _statusMessage = "Yüz Analizi Yapılıyor...";
    });

    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      await _voiceService.speak("Seni gördüm ama yüzünü tam seçemedim. Adın nedir?");
      _listenForNameAndRegister([]); 
      return;
    }

    Face detectedFace = faces.first;

    // --- Kafa Açısı Kontrolü ---
    // Eğer kişi sağa/sola çok bakıyorsa
    double? rotY = detectedFace.headEulerAngleY; 
    if (rotY != null && (rotY > 15 || rotY < -15)) {
       await _voiceService.speak("Lütfen bana doğru bakar mısın? Yüzünü tam göremiyorum.");
       // Yüzü tam göremediğimiz için risk almayıp isim soruyoruz veya tekrar denetiyoruz
       // Basitlik olması için burada doğrudan isim soruyoruz:
       _listenForNameAndRegister([]);
       return;
    }

    List<double> realEmbedding =
    await _faceService.getFaceEmbedding(imagePath, detectedFace);

    if (realEmbedding.isEmpty) {
       await _voiceService.speak("Yüzünü netleştiremedim, biraz yaklaşır mısın?");
       _listenForNameAndRegister([]);
       return;
    }

    // Veritabanından Kontrol
    print("Yüz İmzası (Temiz): $realEmbedding");
    String? recognizedUser = await _faceService.recognizeFace(realEmbedding);

    if (recognizedUser != null) {
      await _voiceService.speak("Merhaba $recognizedUser, seni tekrar gördüm.");
      _geminiService.resetContext(); 
      _startChatLoop();
    } else {
      await _voiceService.speak("Merhaba, seni daha önce görmemiştim. Adın nedir?");
      _listenForNameAndRegister(realEmbedding);
    }
  }

  void _listenForNameAndRegister(List<double> faceEmbedding) {
    if (!_isChatting) return;

    setState(() => _statusMessage = "İsim Bekleniyor...");
    
    Timer? timeoutTimer = Timer(const Duration(seconds: 8), () async {
      if (_isChatting && mounted) {
        await _voiceService.speak("Sesini duyamadım. Devriyeye dönüyorum.");
        _returnToPatrol(turnAway: false);
      }
    });

    _voiceService.listen(onResult: (text) async {
      timeoutTimer.cancel();
      
      if (text.isNotEmpty) {
        String cleanName = text.split(' ').last; 

        // Firebase Kayıt (Embedding ile beraber)
        // FaceService.registerFace metodunu kullanıyoruz
        await _faceService.registerFace(userId: cleanName, embedding: faceEmbedding);
        
        // Ayrıca kullanıcı detayları
        await _firestore.collection('users').doc(cleanName).set({
          'name': cleanName,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _voiceService.speak("Memnun oldum $cleanName, yüzünü hafızama kaydettim.");
        
        _geminiService.resetContext();
        await Future.delayed(const Duration(seconds: 1));
        _startChatLoop();
      }
    });
  }

    void _startChatLoop() {
    if (!_isChatting) return;

    setState(() => _statusMessage = "Dinliyorum (Komut ver)...");

    _voiceService.listen(onResult: (text) async {
      if (text.isEmpty) return;
      
      String cleanText = text.toLowerCase();
      print("Duyulan: $cleanText");

      //        1. ÖZEL KOMUTLAR (Gemini'ye gitmeden çalışır)
      
      // Anahtar Kelimeler: "komut" veya "robot"
      if (cleanText.contains("komut") || cleanText.contains("robot")) {
        
        // A. Hareket Komutları
        if (cleanText.contains("ileri")) {
          await _voiceService.speak("İleri gidiyorum.");
          _moveRobot("ileri", durationMs: 2000); // 2 saniye git
        } 
        else if (cleanText.contains("geri")) {
          await _voiceService.speak("Geri geliyorum.");
          _moveRobot("geri", durationMs: 1000);
        }
        else if (cleanText.contains("sağ")) {
          await _voiceService.speak("Sağa dönüyorum.");
          _moveRobot("sag", durationMs: 800);
        }
        else if (cleanText.contains("sol")) {
          await _voiceService.speak("Sola dönüyorum.");
          _moveRobot("sol", durationMs: 800);
        }
        else if (cleanText.contains("dur")) {
          await _voiceService.speak("Durdum.");
          _moveRobot("dur");
        }

        // Komutu uyguladıktan sonra tekrar dinlemeye geç
        _startChatLoop();
        return;
      }

      //        2. OTONOM MODA GEÇİŞ (Sesle)
      // "Devriyeye başla", "Otonom moda geç", "İşine dön"
      if (cleanText.contains("devriye") || 
          cleanText.contains("otonom") || 
          cleanText.contains("sohbeti kapat")) {
        
        await _voiceService.speak("Tamam, devriye moduna geçiyorum. Görüşürüz.");
        
        // İnsanları görmezden gelerek devriyeye dön (Takılı kalmasın)
        _returnToPatrol(turnAway: true); 
        return; 
      }

      //       3. SOHBETİ BİTİRME
      if (cleanText.contains("güle güle") || cleanText.contains("bay bay") || cleanText.contains("kapat") || cleanText.contains("çıkış yap")) {
        await _voiceService.speak("Görüşmek üzere.");
        _returnToPatrol(turnAway: true);
        return;
      }

      //       4. GEMINI AI (Normal Sohbet)
      // Yukarıdaki komutlar yoksa yapay zekaya sor
      String chatPrompt = "$text. (Kısa ve öz cevap ver)";
      
      try {
        final aiResponse = await _geminiService.generateContent(prompt: chatPrompt);
        
        // Parantez içindeki teknik yazıları temizle [ACTION] vs.
        String speechText = aiResponse.replaceAll(RegExp(r'\[.*?\]'), '');
        
        await _voiceService.speak(speechText);
      } catch (e) {
        await _voiceService.speak("Bağlantı hatası oluştu.");
      }

      // Cevap verdikten sonra tekrar dinle
      if (_isChatting) {
        _startChatLoop();
      }
    });
  }

  // ===========================================================================
  //           4. DEVRİYEYE DÖNÜŞ (TAKILMAYI ÖNLEYEN MANTIK) 
  // ===========================================================================

  void _returnToPatrol({bool turnAway = false}) async {
    print("Devriyeye dönülüyor...");
    
    setState(() {
      _isChatting = false;
      _statusMessage = "Devriye Moduna Dönülüyor...";
      _ignoreHumans = true; // 3 Saniye boyunca insan görme!
    });

    if (turnAway) {
      // İnsanla işim bitti, arkamı döneyim veya yana kaçayım
      _sendCommandToArduino("sag");
      await Future.delayed(const Duration(milliseconds: 1000));
      _sendCommandToArduino("dur");
    }

    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        _isPatrolMode = true;
        _isProcessing = false;
        _ignoreHumans = false; // Artık tekrar insan görebilirim
        _robotState = RobotState.searching;
      });
      _startPatrolLoop();
    }
  }

  // ===========================================================================
  //         UI VE YARDIMCI
  // ===========================================================================

  void _sendCommandToArduino(String command) {
    if (_hardwareService.isConnected) {
      _hardwareService.send("M", command.toLowerCase()); 
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone, Permission.bluetoothConnect, Permission.bluetoothScan].request();
  }

  Future<void> _initBluetooth() async {
    try {
      var devices = await _hardwareService.getPairedDevices();
      setState(() {
        _devicesList = devices;
        if (_devicesList.isNotEmpty) _selectedDevice = _devicesList.first;
      });
    } catch(e) { }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('AI Robot - v2.0'), centerTitle: true),
      body: Column(
        children: [
          // KAMERA DÜZELTME: AspectRatio kullanımı
          if (_cameraController != null && _cameraController!.value.isInitialized)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.40,
              width: double.infinity,
              child: _cameraController == null || !_cameraController!.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width,
                                height: MediaQuery.of(context).size.width * _cameraController!.value.aspectRatio,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                            child: const Text("CANLI", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
            )
          else
             const SizedBox(height: 300, child: Center(child: Text("Kamera bekleniyor..."))),
          
          // Bilgi Paneli (Scrollable text)
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              width: double.infinity,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text("DURUM: $_statusMessage", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text("📍 $_buildingContext", style: const TextStyle(fontSize: 10, color: Colors.grey), maxLines: 2),
                    const SizedBox(height: 8),
                    Text("Navigasyon: $_navigationLog"),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButton<BluetoothDevice>(
                    isExpanded: true,
                    hint: const Text("Arduino Seç"),
                    value: _selectedDevice,
                    items: _devicesList.map((d) => DropdownMenuItem(value: d, child: Text(d.name ?? "-"))).toList(),
                    onChanged: (d) => setState(() => _selectedDevice = d),
                  ),
                  ElevatedButton(
                    onPressed: () { if(_selectedDevice != null) _hardwareService.connect(_selectedDevice!).then((v)=>setState((){})); },
                    child: Text(_hardwareService.isConnected ? "Bağlantıyı Kes" : "Bağlan"),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPatrolMode ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _toggleAutonomousMode,
                      icon: Icon(_isPatrolMode ? Icons.stop : Icons.play_arrow),
                      label: Text(_isPatrolMode ? "DEVRİYEYİ DURDUR" : "OTONOM MODU BAŞLAT"),
                    ),
                  ),

                  const SizedBox(height: 10),
                  const Text("Manuel Kontrol", style: TextStyle(color: Colors.grey)),
                  
                   Row(mainAxisAlignment: MainAxisAlignment.center, children: [_manualBtn(Icons.arrow_upward, "ileri")]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _manualBtn(Icons.arrow_back, "sol"),
                        const SizedBox(width: 20),
                        _manualBtn(Icons.stop, "dur", color: Colors.red),
                        const SizedBox(width: 20),
                        _manualBtn(Icons.arrow_forward, "sag"),
                      ],
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [_manualBtn(Icons.arrow_downward, "geri")]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualBtn(IconData icon, String command, {Color color = Colors.blue}) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(12), backgroundColor: color, foregroundColor: Colors.white),
        onPressed: () => _sendCommandToArduino(command),
        child: Icon(icon),
      ),
    );
  }
}

