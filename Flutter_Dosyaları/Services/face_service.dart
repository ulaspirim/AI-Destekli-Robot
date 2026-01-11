import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class FaceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Yüz embedding kaydı
  Future<void> registerFace({
    required String userId,
    required List<double> embedding,
  }) async {
    await _firestore.collection('faces').doc(userId).set({
      'embedding': embedding,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Kayıtlı yüzlerle karşılaştır
  Future<String?> recognizeFace(List<double> embedding) async {
    final faces = await _firestore.collection('faces').get();

    double minDistance = double.infinity;
    String? matchedUser;
    
    // --- KRİTİK AYAR ---
    // Bu değer ne kadar küçükse robot o kadar "seçici" olur.
    // 0.35 -> Herkesi tanır (Hatalı)
    // 0.08 -> İdeal (Benzerleri ayırt eder)
    // 0.05 -> Çok sıkı (Seni bile bazen tanımaz)
    double threshold = 0.08; 

    for (var doc in faces.docs) {
      // Veritabanından gelen liste dynamic olabilir, cast önemli
      final List stored = doc['embedding'];
      
      // Boyut kontrolü
      if (stored.length != embedding.length) continue; 

      // Cosine yerine Euclidean kullanıyoruz (Daha hassas)
      final distance = _calculateEuclideanDistance(
        embedding,
        stored.cast<double>(),
      );

      print("Kullanıcı: ${doc.id} - Fark: $distance"); // Konsoldan takip et!

      if (distance < threshold && distance < minDistance) {
        minDistance = distance;
        matchedUser = doc.id;
      }
    }
    return matchedUser;
  }

  // Cosine Distance yerine Öklid Mesafesi kullanıyoruz.
  // Çünkü senin verilerin (göz-burun mesafesi) geometrik uzunluklar.
  double _calculateEuclideanDistance(List<double> v1, List<double> v2) {
    double sum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      // (x1 - x2)^2 mantığı
      sum += pow((v1[i] - v2[i]), 2);
    }
    return sqrt(sum);
  }
}