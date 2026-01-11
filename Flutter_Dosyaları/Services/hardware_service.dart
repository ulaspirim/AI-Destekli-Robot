import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class HardwareService {
  BluetoothConnection? connection;
  bool isConnecting = false;

  // Bağlantı durumu değiştiğinde Main dosyasına haber vermek için callback
  Function(bool isConnected)? onConnectionChanged;

  // Getter
  bool get isConnected => connection != null && connection!.isConnected;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      print("Cihaz listesi alınırken hata: $e");
      return [];
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    if (isConnected) {
      await disconnect();
    }

    isConnecting = true;
    
    try {
      // 10 saniye içinde bağlanamazsa hata fırlat
      connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 10));

      print('✅ Cihaza bağlanıldı: ${device.name}');
      
      // Bağlantı başarılı, UI'a haber ver
      if (onConnectionChanged != null) onConnectionChanged!(true);

      // KOPMA DİNLEYİCİSİ
      connection!.input!.listen(
        (Uint8List data) {
          // Arduino'dan gelen veri olursa burada okunur.
          // String gelenMesaj = utf8.decode(data);
          // print("Arduino'dan gelen: $gelenMesaj");
        },
        onDone: () {
          print('⚠️ Bağlantı koptu.');
          connection = null;
          isConnecting = false;
          // UI'a haber ver: Bağlantı gitti!
          if (onConnectionChanged != null) onConnectionChanged!(false);
        },
        onError: (error) {
          print('❌ Bağlantı hatası: $error');
          connection = null;
          isConnecting = false;
          if (onConnectionChanged != null) onConnectionChanged!(false);
        },
      );

      isConnecting = false;
      return true;

    } catch (e) {
      print('Bluetooth bağlantı hatası: $e');
      connection = null;
      isConnecting = false;
      return false;
    }
  }

  Future<void> send(String prefix, String data) async {
    if (isConnected) {
      // Arduino için format: "M,ileri\n"
      String messageToSend = "$prefix,$data\n";
      try {
        connection!.output.add(Uint8List.fromList(utf8.encode(messageToSend)));
        await connection!.output.allSent;
        print("📤 Gönderildi: ${messageToSend.trim()}");
      } catch (e) {
        print("Gönderme hatası: $e");
        // Hata alındıysa bağlantıyı düşür
        disconnect();
      }
    } else {
      print("Bağlı cihaz yok, komut gitmedi.");
    }
  }

  Future<void> disconnect() async {
    await connection?.close();
    connection = null;
    isConnecting = false;
    if (onConnectionChanged != null) onConnectionChanged!(false);
  }

  void dispose() {
    disconnect();
  }
}