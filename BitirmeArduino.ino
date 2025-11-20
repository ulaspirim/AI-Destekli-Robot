#include <LiquidCrystal_I2C.h> // I2C LCD Kütüphanesi

LiquidCrystal_I2C lcd(0x27, 16, 2); 

// HC-05 bağlantısı (Sizin kodunuzla aynı)
char receivedChar;
String receivedData = "";
bool newData = false;

// Motor pinleri (Sizin kodunuzla aynı)
const int motor1Pin1 = 2;
const int motor1Pin2 = 3;
const int motor2Pin1 = 4;
const int motor2Pin2 = 5;

const int ENA = 6;  // Sol motorun hız pini
const int ENB = 9;  // Sağ motorun hız pini

int motorSpeed = 100;  // Varsayılan hız

// LCD kayan yazı değişkenleri
String line1 = "Robot Baslatildi... "; // Üst satır (line 0)
String line2 = "Bekleniyor... ";      // Alt satır (line 1)
int scrollIndex1 = 0;
int scrollIndex2 = 0;
unsigned long lastScrollTime = 0;
const int scrollDelay = 300; // ms cinsinden kayma hızı

void setup() {
  Serial.begin(9600);
  Serial1.begin(9600);

  lcd.init();
  lcd.backlight();
  lcd.clear();

  pinMode(motor1Pin1, OUTPUT);
  pinMode(motor1Pin2, OUTPUT);
  pinMode(motor2Pin1, OUTPUT);
  pinMode(motor2Pin2, OUTPUT);
  pinMode(ENA, OUTPUT);
  pinMode(ENB, OUTPUT);

  stopMotors();

  Serial.println("Arduino ve HC-05 baslatildi. Serial1 portu dinleniyor.");
}

void loop() {
  // Bluetooth verisi geldi mi?
  if (Serial1.available()) {
    receivedChar = Serial1.read();
    if (receivedChar == '\n') {
      newData = true;
    } else {
      receivedData += receivedChar;
    }
  }

  if (newData) {
    receivedData.trim(); // <<--- BU SATIRI EKLE
    Serial.print("Alinan Bluetooth verisi: ");
    Serial.println(receivedData);

    int commaIndex = receivedData.indexOf(',');
    if (commaIndex != -1) {
      String prefix = receivedData.substring(0, commaIndex);
      String value = receivedData.substring(commaIndex + 1);
      Serial.println("Prefix: " + prefix + " | Value: " + value);


      // --- İsteğinize göre güncellenmiş yönlendirme ---
      if (prefix == "M") { 
        setLineText(1, "Motor: " + value); // <-- DEĞİŞTİ: Alt satır (line 1)
        if (value == "ileri") {
          stopMotors();
          delay(50);
          moveForward();
        } 
        else if (value == "geri"){
          stopMotors();
          delay(50);
          moveBackward();
        } 
        else if (value == "sol"){
          stopMotors();
          delay(50);
          turnLeft();
        } 
        else if ( value == "sag" || value == "sağ") {
          stopMotors();
          delay(50);
          turnRight();
        }
          
        else if (value == "dur") {
          stopMotors();
          delay(50);
        }
          

      } else if (prefix == "C") { 
        setLineText(0, "Sohbet: " + value); // <-- DEĞİŞTİ: Üst satır (line 0)

      } else if (prefix == "T") { 
        // 'T' komutu da alt satıra yazsın istediniz.
        setLineText(1, "Baglanti Testi: OK"); // <-- DEĞİŞTİ: Alt satır (line 1)
        Serial1.println("ACK\n");
      }
    }

    receivedData = "";
    newData = false;
  }

  // Sürekli kayan yazı efektini güncelle
  updateScrollingDisplay();
}

// =============================
// LCD KAYAN YAZI FONKSIYONLARI
// =============================

// <-- YENİ FONKSİYON: Satır metnini günceller ve indeksi sıfırlar
void setLineText(int line, String text) {
  // Düzgün bir kaydırma döngüsü için metnin sonuna biraz boşluk ekle
  String paddedText = text + "   "; 
  
  if (line == 0) {
    line1 = paddedText;
    scrollIndex1 = 0; // Yeni metin geldi, kaydırmayı baştan başlat
  } else if (line == 1) {
    line2 = paddedText;
    scrollIndex2 = 0; // Yeni metin geldi, kaydırmayı baştan başlat
  }
}

// <-- YENİ FONKSİYON: Kısa metinleri sabit, uzun metinleri kayan şekilde gösterir
void updateScrollingDisplay() {
  // Belirlenen gecikme süresi dolmadıysa fonksiyondan çık
  if (millis() - lastScrollTime < scrollDelay) return;
  
  lastScrollTime = millis();

  // --- Satır 1 (Üst Satır) İşlemleri ---
  lcd.setCursor(0, 0);
  if (line1.length() <= 16) {
    // Metin 16 karakterden kısaysa veya eşitse, kaydırma yapma
    lcd.print(line1);
    // Satırın geri kalanını temizle
    for (int i = line1.length(); i < 16; i++) {
      lcd.print(" ");
    }
  } else {
    // Metin 16 karakterden uzunsa, kaydırma yap
    // Başa dönme efekti için metnin başını (16 karakter) kopyalayıp sonuna ekliyoruz
    String scrollText1 = line1 + line1.substring(0, 16); 
    String displayLine1 = scrollText1.substring(scrollIndex1, scrollIndex1 + 16);
    lcd.print(displayLine1);
    
    scrollIndex1++;
    if (scrollIndex1 >= line1.length()) { // Ana metnin sonuna geldiyse
      scrollIndex1 = 0; // Başa dön
    }
  }

  // --- Satır 2 (Alt Satır) İşlemleri ---
  lcd.setCursor(0, 1);
  if (line2.length() <= 16) {
    // Metin 16 karakterden kısaysa veya eşitse, kaydırma yapma
    lcd.print(line2);
    // Satırın geri kalanını temizle
    for (int i = line2.length(); i < 16; i++) {
      lcd.print(" ");
    }
  } else {
    // Metin 16 karakterden uzunsa, kaydırma yap
    String scrollText2 = line2 + line2.substring(0, 16);
    String displayLine2 = scrollText2.substring(scrollIndex2, scrollIndex2 + 16);
    lcd.print(displayLine2);

    scrollIndex2++;
    if (scrollIndex2 >= line2.length()) {
      scrollIndex2 = 0;
    }
  }
}


// =============================
// MOTOR KONTROL FONKSIYONLARI
// =============================
void moveForward() {
  analogWrite(ENA, motorSpeed);
  analogWrite(ENB, motorSpeed);
  digitalWrite(motor1Pin1, HIGH);
  digitalWrite(motor1Pin2, LOW);
  digitalWrite(motor2Pin1, LOW);
  digitalWrite(motor2Pin2, HIGH);
}

void moveBackward() {
  analogWrite(ENA, motorSpeed);
  analogWrite(ENB, motorSpeed);
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, HIGH);
  digitalWrite(motor2Pin1, HIGH);
  digitalWrite(motor2Pin2, LOW);
}

void turnLeft() {
  analogWrite(ENA, motorSpeed / 10);  // Sol motor yavaş
  analogWrite(ENB, motorSpeed);      // Sağ motor hızlı
  digitalWrite(motor1Pin1, HIGH);
  digitalWrite(motor1Pin2, LOW);
  digitalWrite(motor2Pin1, HIGH);
  digitalWrite(motor2Pin2, LOW);
}

void turnRight() {
  analogWrite(ENA, motorSpeed);      // Sol motor hızlı
  analogWrite(ENB, motorSpeed / 10);  // Sağ motor yavaş
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, HIGH);
  digitalWrite(motor2Pin1, LOW);
  digitalWrite(motor2Pin2, HIGH);
}

void stopMotors() {
  analogWrite(ENA, 0);
  analogWrite(ENB, 0);
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, LOW);
  digitalWrite(motor2Pin1, LOW);
  digitalWrite(motor2Pin2, LOW);
}