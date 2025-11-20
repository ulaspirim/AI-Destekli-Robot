import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
// If you see "Target of URI doesn't exist", add this dependency to pubspec.yaml:
// flutter_bluetooth_serial: ^0.2.2
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Gemini API anahtarınızı buraya girin.
// ignore: constant_identifier_names
const String GEMINI_API_KEY = "Buraya Kodu Yapistirin"; // <<-- BURAYI KENDİ ANAHTARINIZLA DEĞİŞTİRİN!

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const AiTestApp());
}

class AiTestApp extends StatelessWidget {
  const AiTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Test Uygulaması',
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
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
  CameraController? _cameraController;
  Timer? _cameraTimer;
  String _geminiVisionResponse = "Görüntü analiz yanıtı bekleniyor...";
  String _geminiChatResponse = "Sohbet yanıtı bekleniyor...";
  String _speechText = "Konuşmak için basılı tutun...";
  String _lastSpokenResponse = "";

  // STT ve TTS
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  // Bluetooth Bağlantısı
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool get isConnected => connection != null && connection!.isConnected;
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _selectedDevice;

  Timer? _speechCycleTimer;
  bool _isSpeakingAllowed = true; // Konuşmanın şu an serbest olup olmadığını tutar
  static const int _listeningDurationSeconds = 10;
  static const int _pauseDurationSeconds = 10;

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // İzinleri burada isteyin
    _initializeCamera();
    _initSpeech();
    _initTts();
    _initBluetooth(); // Bluetooth başlatma
    _startSpeechCycle();
  }

  Future<void> _initBluetooth() async {
    FlutterBluetoothSerial.instance.state.then((state) {
      if (state == BluetoothState.STATE_OFF) {
        FlutterBluetoothSerial.instance.requestEnable();
      }
    });

    FlutterBluetoothSerial.instance.getBondedDevices().then((devices) {
      setState(() {
        _devicesList = devices;
      });
      // HC-05'i otomatik olarak bulmaya çalış
      _selectedDevice = _devicesList.cast<BluetoothDevice?>().firstWhere(
      (device) => device?.name?.toLowerCase().contains("hc-05") ?? false,
      orElse: () => _devicesList.isEmpty ? null : _devicesList.first,
      );
      if (_selectedDevice != null) {
        _connectToBluetooth(_selectedDevice!);
      } else {
        print("HC-05 veya başka bir Bluetooth cihazı bulunamadı.");
      }
    });
  }

  Future<void> _connectToBluetooth(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
    });
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      print('Bağlandı: ${device.name}');
      setState(() {
        isConnecting = false;
        _selectedDevice = device;
      });
      // Bağlantı başarılı olduğunda bir test mesajı gönder
      _sendToBluetooth("T", "Bağlantı Testi");

      connection!.input!.listen((Uint8List data) {
        // Gelen veriyi burada işleyebilirsiniz (Arduino'dan gelen yanıtlar gibi)
        print('Bluetoothdan gelen veri: ${ascii.decode(data)}');
      }).onDone(() {
        print('Bluetooth bağlantısı kesildi.');
        setState(() {
          connection = null;
          isConnecting = false;
        });
      });
    } catch (exception) {
      print('Bluetooth bağlantı hatası: $exception');
      setState(() {
        isConnecting = false;
        connection = null;
      });
      showInSnackBar('Bluetooth bağlantısı kurulamadı: $exception');
    }
  }

  Future<void> _sendToBluetooth(String prefix, String data) async {
    if (isConnected) {
      // Arduino'nun anlayacağı bir format: "PREFİX,SATIR1,SATIR2\n"
      // HC-05'e göndermek için genellikle basit bir string yeterlidir.
      String messageToSend = "$prefix,$data\n";

      try {
        connection!.output.add(Uint8List.fromList(utf8.encode(messageToSend)));
        await connection!.output.allSent;
        print("Bluetooth'a gönderildi: $messageToSend");
      } catch (e) {
        print("Bluetooth'a yazma hatası: $e");
        setState(() {
          connection = null; // Bağlantı hatası durumunda bağlantıyı sıfırla
        });
        showInSnackBar('Bluetootha veri gönderilirken hata oluştu: $e');
      }
    } else {
      print("Bluetooth bağlı değil, gönderilemedi.");
      showInSnackBar('Bluetooth bağlı değil. Lütfen bağlanın.');
    }
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      setState(() {
        _geminiVisionResponse = "Kamera bulunamadı.";
      });
      return;
    }

    // Ön kamerayı bul
    CameraDescription? frontCamera;
    for (CameraDescription camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        frontCamera = camera;
        break;
      }
    }

    // Eğer ön kamera bulunamazsa, varsayılan olarak ilk kamerayı kullan (genellikle arka)
    if (frontCamera == null) {
      setState(() {
        _geminiVisionResponse = "Ön kamera bulunamadı. İlk kamera kullanılıyor.";
      });
      _cameraController = CameraController(
        cameras[0], // Ön kamera bulunamazsa ilk kamerayı kullan
        ResolutionPreset.medium,
        enableAudio: false,
      );
    } else {
      // Ön kamera bulundu, onu kullan
      _cameraController = CameraController(
        frontCamera, // Ön kamerayı burada kullanıyoruz
        ResolutionPreset.medium,
        enableAudio: false,
      );
    }

    _cameraController!.addListener(() {
      if (mounted) setState(() {});
    });

    try {
      await _cameraController!.initialize();
      _startImageStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  void _startImageStreaming() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Her 10 saniyede bir görüntü alıp Gemini'ye gönder
    _cameraTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_cameraController!.value.isTakingPicture) {
        try {
          final XFile file = await _cameraController!.takePicture();
          _sendImageToGemini(file.path);
        } catch (e) {
          print("Hata oluştu: Kamera görüntüsü alınamadı: $e");
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    var microphoneStatus = await Permission.microphone.status;
    if (microphoneStatus.isDenied) {
      await Permission.microphone.request();
    }
    var bluetoothConnectStatus = await Permission.bluetoothConnect.status;
    if (bluetoothConnectStatus.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    var bluetoothScanStatus = await Permission.bluetoothScan.status;
    if (bluetoothScanStatus.isDenied) {
      await Permission.bluetoothScan.request();
    }
  }

  Future<void> _sendImageToGemini(String imagePath) async {
    setState(() {
      _geminiVisionResponse = "Görüntü analiz ediliyor...";
    });
    try {
      final bytes = await File(imagePath).readAsBytes();
      final img_lib.Image? originalImage = img_lib.decodeImage(bytes);

      if (originalImage == null) {
        setState(() {
          _geminiVisionResponse = "Görüntü çözümlenemedi.";
        });
        return;
      }

      // Gemini'ye uygun boyuta yeniden boyutlandır (opsiyonel)
      final img_lib.Image resizedImage = img_lib.copyResize(originalImage, width: 600);
      final List<int> resizedBytes = img_lib.encodeJpg(resizedImage);
      final String base64Image = base64Encode(resizedBytes);

      final response = await http.post(
        Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": "Bu görüntüde ne görüyorsun? Ana nesneleri tanımla ve insan varsa belirt. Sadece birkaç cümle ile özetle."},
                {
                  "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": base64Image,
                  }
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String geminiText = data['candidates'][0]['content']['parts'][0]['text'] ?? "Yanıt alınamadı.";
        setState(() {
          _geminiVisionResponse = "Görüntü Analizi: $geminiText";
        });
        // Görüntü metnini de Bluetooth üzerinden gönder

      } else {
        setState(() {
          _geminiVisionResponse = "API Hatası: ${response.statusCode}, ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        _geminiVisionResponse = "Görüntü gönderme hatası: $e";
      });
    }
  }

  // --- Speech to Text (STT) ---
  bool _speechEnabled = false;
  bool _isListeningContinuously = false; // Sürekli dinleme durumunu takip etmek için
  Timer? _speechRestartTimer; // Dinlemeyi yeniden başlatmak için timer

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onStatus: (status) {
        print('STT Status: $status');
        if (status == 'done') {
          print("STT dinleme döngüsü tamamlandı, yeniden başlatma bekleniyor.");
        }
      },
      onError: (errorNotification) {
        print('STT Error: $errorNotification');
        print("STT hata oluştu, yeniden başlatma bekleniyor.");
      },
    );
    setState(() {});
  }

  void _startSpeechCycle() {
    // Mevcut döngüyü iptal et
    _speechCycleTimer?.cancel();
    _speechToText.stop(); // Önceki dinlemeyi durdur

    // İlk olarak dinlemeyi başlat
    _startListeningPeriod();

    // Ardından döngüyü kur
    _speechCycleTimer = Timer.periodic(
      Duration(seconds: _listeningDurationSeconds + _pauseDurationSeconds),
      (timer) {
        // Dinleme süresini başlat
        _startListeningPeriod();
        // Belirli bir süre sonra dinlemeyi durdur ve bekleme süresini başlat
        Timer(Duration(seconds: _listeningDurationSeconds), () {
          _stopListeningPeriod();
        });
      },
    );
  }

  void _startListeningPeriod() async {
    if (_speechEnabled) {
      setState(() {
        _speechText = "Dinliyor ($_listeningDurationSeconds saniye)...";
        _isSpeakingAllowed = true;
      });
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _speechText = result.recognizedWords;
          });
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _sendTextToGemini(_speechText);
            _speechText = "Yanıt bekleniyor...";
          }
        },
        listenFor: Duration(seconds: _listeningDurationSeconds),
        pauseFor: const Duration(seconds: 2), // Kısa duraklamalara izin ver
        localeId: 'tr_TR',
      );
      print("Dinleme başlatıldı.");
    }
  }

  void _stopListeningPeriod() async {
    await _speechToText.stop();
    setState(() {
      _speechText = "Konuşma kapalı ($_pauseDurationSeconds saniye bekleme)...";
      _isSpeakingAllowed = false;
    });
    print("Dinleme durduruldu.");
  }

  void _startContinuousListening() {
    if (_speechEnabled && !_speechToText.isListening) {
      _isListeningContinuously = true;
      _startListening();
    }
  }

  void _startListening() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    setState(() {
      _speechText = "Dinliyor...";
    });
    await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _speechText = result.recognizedWords;
          });
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _sendTextToGemini(_speechText);
            _speechText = "Konuşmak için hazır...";
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'tr_TR',
        onSoundLevelChange: (level) {});
  }

  void _stopListening() async {
    _isListeningContinuously = false;
    _speechRestartTimer?.cancel();
    await _speechToText.stop();
    setState(() {
      _speechText = "Konuşma sonlandırıldı.";
    });
  }

  Future<void> _sendTextToGemini(String userText) async {
    setState(() {
      _geminiChatResponse = "Metin analiz ediliyor...";
    });
    try {
      final response = await http.post(
        Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": "Kullanıcı dedi ki: '$userText'. Ona nasıl bir yanıt verebilirsin? Lütfen sadece çok kısa ve öz bir yanıt ver. Sakın lafı uzatma."}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String geminiTextResponse = data['candidates'][0]['content']['parts'][0]['text'] ?? "Yanıt alınamadı.";
        setState(() {
          _geminiChatResponse = "Gemini: $geminiTextResponse";
          _lastSpokenResponse = geminiTextResponse;
        });
        _speak(_lastSpokenResponse); // Yanıtı sesli oku
        _sendToBluetooth("C", geminiTextResponse); // Sohbet yanıtını Bluetooth üzerinden gönder
      } else {
        setState(() {
          _geminiChatResponse = "API Hatası (Sohbet): ${response.statusCode}, ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        _geminiChatResponse = "Metin gönderme hatası: $e";
      });
    }
  }

  // --- Text to Speech (TTS) ---
  void _initTts() async {
    _flutterTts.setLanguage("tr-TR");
    _flutterTts.setSpeechRate(0.8);
    _flutterTts.setErrorHandler((msg) {
      print("TTS Hata: $msg");
      setState(() {
        _geminiChatResponse = "TTS hatası: $msg";
      });
    });
    _flutterTts.setCompletionHandler(() {
      print("TTS konuşma tamamlandı.");
      if (_isListeningContinuously) {
        _speechRestartTimer?.cancel();
        _speechRestartTimer = Timer(const Duration(milliseconds: 1000), () {
          _startListening();
        });
      }
    });
  }

  Future _speak(String text) async {
    if (text.isNotEmpty) {
      // Konuşma başlamadan önce dinlemeyi durdur
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
      await _flutterTts.speak(text);
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Hata: ${e.code}\n${e.description}');
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void logError(String code, String? message) {
    if (message != null) {
      print('Hata: $code\nMesaj: $message');
    } else {
      print('Hata: $code');
    }
  }

  @override
  void dispose() {
    _cameraTimer?.cancel();
    _cameraController?.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    _speechCycleTimer?.cancel();
    connection?.dispose(); // Bluetooth bağlantısını dispose et
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI Test Uygulaması')),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4, // Ekranın %40'ı
              child: CameraPreview(_cameraController!),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                    _geminiVisionResponse,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(),
                  Text(
                    _geminiChatResponse,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(),
                  Text(
                    'Siz: $_speechText',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      FloatingActionButton(
                        onPressed: _speechToText.isListening ? _stopListening : _startContinuousListening,
                        tooltip: 'Konuş',
                        heroTag: 'micBtn', // Benzersiz tag
                        child: Icon(_speechToText.isNotListening ? Icons.mic_off : Icons.mic),
                      ),
                      FloatingActionButton(
                        onPressed: () => _speak(_lastSpokenResponse),
                        tooltip: 'Son Yanıtı Tekrarla',
                        heroTag: 'volumeBtn', // Benzersiz tag
                        child: const Icon(Icons.volume_up),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Bluetooth cihaz listesi ve bağlan/kes butonları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      DropdownButton<BluetoothDevice>(
                        hint: const Text("Cihaz Seçin"),
                        value: _selectedDevice,
                        onChanged: isConnecting
                            ? null
                            : (BluetoothDevice? device) {
                                setState(() {
                                  _selectedDevice = device;
                                });
                              },
                        items: _devicesList
                            .map((_device) => DropdownMenuItem(
                                  value: _device,
                                  child: Text(_device.name ?? "Bilinmeyen Cihaz"),
                                ))
                            .toList(),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: isConnecting
                            ? null
                            : (isConnected
                                ? () {
                                    connection?.dispose();
                                    setState(() {
                                      connection = null;
                                    });
                                  }
                                : (_selectedDevice == null
                                    ? null
                                    : () => _connectToBluetooth(_selectedDevice!))),
                        child: Text(isConnecting ? 'Baglaniyor...' : (isConnected ? 'Baglantiyi Kes' : 'Baglan')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isConnected ? 'Bluetooth Baglı: ${_selectedDevice?.name}' : 'Bluetooth Baglı Değil',
                    style: TextStyle(
                        color: isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  // Motor kontrol butonları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                        onPressed: isConnected ? () => _sendToBluetooth("M", "ileri") : null,
                        child: const Text("İleri"),
                      ),
                      ElevatedButton(
                        onPressed: isConnected ? () => _sendToBluetooth("M", "dur") : null,
                        child: const Text("Dur"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                        onPressed: isConnected ? () => _sendToBluetooth("M", "sol") : null,
                        child: const Text("Sol"),
                      ),
                      ElevatedButton(
                        onPressed: isConnected ? () => _sendToBluetooth("M", "sag") : null,
                        child: const Text("Sağ"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: isConnected ? () => _sendToBluetooth("M", "geri") : null,
                    child: const Text("Geri"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}