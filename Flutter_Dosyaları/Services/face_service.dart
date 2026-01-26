import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img; // Resim işleme kütüphanesi
import 'package:tflite_flutter/tflite_flutter.dart'; // AI Motoru
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FaceService {
  Interpreter? _interpreter;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- AYARLAR ---
  // MobileFaceNet modeli 112x112 piksel resim ister.
  static const int INPUT_SIZE = 112; 
  
  // EŞİK DEĞERİ (THRESHOLD) ÇOK ÖNEMLİ:
  // Eski kodundaki 0.08 çok düşüktü çünkü sadece 5 tane oran vardı.
  // Şimdi 192 tane sayı kıyaslıyoruz. Bu yüzden mesafe doğal olarak artar.
  // 0.7 ile 1.0 arası idealdir.
  // 0.8 -> Dengeli
  // 0.6 -> Çok sıkı (İkizi bile ayırır ama seni bazen tanımaz)
  // 1.2 -> Gevşek (Herkesi sen sanabilir)
  static const double THRESHOLD = 0.45; 

  /// Servisi başlatır ve Yapay Zeka modelini yükler
  Future<void> initialize() async {
    try {
      // Model dosyasının assets klasöründe olduğundan emin ol!
      // Dosya adı: mobilefacenet.tflite
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      print("✅ TFLite Face Model Başarıyla Yüklendi.");
    } catch (e) {
      print("❌ Model yüklenirken hata oluştu: $e");
      print("Lütfen assets/mobilefacenet.tflite dosyasını kontrol edin.");
    }
  }

  /// 1. Yüzden 192 boyutlu sayısal imza (embedding) üretir
  Future<List<double>> getFaceEmbedding(String imagePath, Face face) async {
    if (_interpreter == null) await initialize();

    // 1. Resmi dosyadan oku
    File imageFile = File(imagePath);
    Uint8List imageBytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) return [];

    // 2. Yüzü resimden kesip al (Crop)
    int x = face.boundingBox.left.toInt();
    int y = face.boundingBox.top.toInt();
    int w = face.boundingBox.width.toInt();
    int h = face.boundingBox.height.toInt();

    // Sınırların dışına taşmayı engelle (Crash olmaması için)
    x = max(0, x);
    y = max(0, y);
    w = min(w, originalImage.width - x);
    h = min(h, originalImage.height - y);

    img.Image croppedFace = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);

    // 3. Resmi modelin istediği boyuta (112x112) getir
    img.Image resizedFace = img.copyResize(croppedFace, width: INPUT_SIZE, height: INPUT_SIZE);

    // 4. Resmi sayı dizisine çevir (Normalization)
    // Model [1, 112, 112, 3] şeklinde 4 boyutlu veri bekler.
    var input = _imageToFloatList(resizedFace);

    // 5. Modeli Çalıştır (Inference)
    // Çıktı olarak [1, 192] boyutunda bir liste verecek.
    var output = List.filled(1 * 192, 0.0).reshape([1, 192]);
    
    _interpreter!.run(input, output);
    List<double> rawEmbedding = List<double>.from(output[0]);

    // HAM VERİYİ KONTROL İÇİN YAZDIR (Debug)
    // Eğer burada 1.0'dan büyük sayılar görüyorsan normaldir.
    // print("Ham veri örneği: ${rawEmbedding.sublist(0, 5)}");

    // NORMALİZASYON (Bunu yapmazsak veritabanı bozulur)
    List<double> normalizedEmbedding = _l2Normalize(rawEmbedding);

    // NORMALIZE VERİYİ KONTROL ET
    // Buradaki sayıların hepsi -1 ile 1 arasında OLMALI.
    // print("Normalize veri örneği: ${normalizedEmbedding.sublist(0, 5)}");

    return normalizedEmbedding;
  }

  /// Resmi AI modelinin anlayacağı Float dizisine çevirir
  List _imageToFloatList(img.Image image) {
    var convertedBytes = Float32List(1 * INPUT_SIZE * INPUT_SIZE * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (var i = 0; i < INPUT_SIZE; i++) {
      for (var j = 0; j < INPUT_SIZE; j++) {
        var pixel = image.getPixel(j, i);
        // RGB Değerlerini Normalize et: (Değer - 128) / 128
        // Bu işlem renkleri -1 ile 1 arasına sıkıştırır.
        buffer[pixelIndex++] = (pixel.r - 128) / 128;
        buffer[pixelIndex++] = (pixel.g - 128) / 128;
        buffer[pixelIndex++] = (pixel.b - 128) / 128;
      }
    }
    return convertedBytes.reshape([1, INPUT_SIZE, INPUT_SIZE, 3]);
  }

  /// 2. Veritabanındaki yüzlerle karşılaştırır
  Future<String?> recognizeFace(List<double> newEmbedding) async {
    try {
      var snapshot = await _firestore.collection('faces').get();
      
      String? bestMatchUser;
      double maxSimilarity = -1.0; // En yüksek benzerliği tutacak değişken

      // --- YENİ EŞİK DEĞERİ ---
      // Cosine Similarity için 0.75 - 0.80 arası idealdir.
      // Eğer herkesi sen sanıyorsa bunu 0.80 veya 0.85 yap.
      double currentThreshold = 0.75; 

      for (var doc in snapshot.docs) {
        String userId = doc['userId'];
        List<dynamic> storedData = doc['embedding'];
        List<double> storedEmbedding = storedData.cast<double>();

        // Embedding boyutları uyuşmazsa atla
        if (newEmbedding.length != storedEmbedding.length) continue;

        // --- DEĞİŞEN KISIM BURASI ---
        // Artık Öklid değil, Cosine Similarity kullanıyoruz.
        double similarity = _cosineSimilarity(newEmbedding, storedEmbedding);
        
        print("🔍 DETAY:");
        print("   -> Kayıtlı Kişi: $userId");
        print("   -> Benzerlik Puanı: $similarity"); // 1.0'a ne kadar yakınsa o kadar iyi

        // Eğer bulduğumuz benzerlik, şu ana kadarki en yüksekten büyükse güncelle
        if (similarity > maxSimilarity) {
          maxSimilarity = similarity;
          bestMatchUser = userId;
        }
      }

      // Döngü bitti. En iyi eşleşme bizim limitimizi (Threshold) geçti mi?
      if (maxSimilarity > currentThreshold) {
        print("   ✅ EŞLEŞME BAŞARILI! Tanınan: $bestMatchUser");
        return bestMatchUser;
      } else {
        print("   ❌ KİMSE TANINAMADI. (En yüksek benzerlik: $maxSimilarity)");
        return null; 
      }

    } catch (e) {
      print("Tanıma hatası: $e");
      return null;
    }
  }

  /// 3. Yeni yüz kaydeder
  Future<void> registerFace({required String userId, required List<double> embedding}) async {
    // Koleksiyon ismini 'faces' olarak standartlaştırdık.
    await _firestore.collection('faces').doc(userId).set({
      'userId': userId,
      'embedding': embedding,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Öklid Mesafesi Hesaplayıcı
  // Bu fonksiyon iki yüz arasındaki benzerliği -1 ile 1 arasında hesaplar.
  double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dotProduct = 0.0;
    double mag1 = 0.0;
    double mag2 = 0.0;

    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      mag1 += v1[i] * v1[i];
      mag2 += v2[i] * v2[i];
    }
    
    // Sıfıra bölme hatasını önlemek için kontrol
    double magnitude = sqrt(mag1) * sqrt(mag2);
    if (magnitude == 0) return 0;

    return dotProduct / magnitude;
  }

  List<double> _l2Normalize(List<double> embedding) {
    double sum = 0;
    // 1. Karelerinin toplamını bul
    for (var x in embedding) {
      sum += x * x;
    }
    // 2. Karekökünü al (Büyüklük/Magnitude)
    double magnitude = sqrt(sum);

    // 3. Her sayıyı büyüklüğe böl
    return embedding.map((e) => e / magnitude).toList();
  }
}
