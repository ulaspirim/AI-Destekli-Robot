#include <LiquidCrystal_I2C.h>

// LCD Ayarları (Adres genelde 0x27 olur)
LiquidCrystal_I2C lcd(0x27, 16, 2); 

// --- BLUETOOTH AYARLARI (MEGA İÇİN) ---
// HC-05 TX ucu -> Arduino Mega Pin 19 (RX1)
// HC-05 RX ucu -> Arduino Mega Pin 18 (TX1)
// Kodda Serial1 kullanıyoruz.

// Değişkenler
char receivedChar;
String receivedData = "";
bool newData = false;

// Motor pinleri (Senin bağlantıların)
const int motor1Pin1 = 2;
const int motor1Pin2 = 3;
const int motor2Pin1 = 4;
const int motor2Pin2 = 5;

const int ENA = 6;  // Sol motor Hız
const int ENB = 9;  // Sağ motor Hız

int motorSpeed = 150;  // Robotun rahat dönmesi için hızı biraz artırdım

// LCD kayan yazı değişkenleri
String line1 = "Sistem Hazir... "; 
String line2 = "Baglanti Bekleniyor";      
int scrollIndex1 = 0;
int scrollIndex2 = 0;
unsigned long lastScrollTime = 0;
const int scrollDelay = 300; 

unsigned long motorStartTime = 0;
unsigned long motorDuration = 1500; // ms (genel süre)
bool motorRunning = false;



void setup() {
  // Bilgisayar ile haberleşme (Serial Monitor)
  Serial.begin(9600);
  
  // Bluetooth ile haberleşme (HC-05 -> Serial1)
  Serial1.begin(9600); 

  // LCD Başlatma
  lcd.init();
  lcd.backlight();
  lcd.clear();
  setLineText(0, "Sistem Basliyor");
  setLineText(1, "Mega2560 Hazir");

  // Pin Modları
  pinMode(motor1Pin1, OUTPUT);
  pinMode(motor1Pin2, OUTPUT);
  pinMode(motor2Pin1, OUTPUT);
  pinMode(motor2Pin2, OUTPUT);
  pinMode(ENA, OUTPUT);
  pinMode(ENB, OUTPUT);

  stopMotors();

  Serial.println("Arduino Mega ve HC-05 (Serial1) baslatildi.");
  delay(1000);
  setLineText(0, "32 UP 53");
  setLineText(1, "Komut Bekleniyor");
}

void loop() {
  // --- Bluetooth Veri Okuma (Serial1) ---
  while (Serial1.available() > 0) {
    receivedChar = Serial1.read();
    if (receivedChar == '\n') { // Flutter her komutun sonuna \n koyar
      newData = true;
      break; 
    } else {
      receivedData += receivedChar;
    }
  }

  if (motorRunning) {
    if (millis() - motorStartTime >= motorDuration) {
      stopMotors();
      motorRunning = false;
      setLineText(1, "Motor Durdu");
    }
  }

  // --- Veri İşleme ---
  if (newData) {
    receivedData.trim(); // Boşlukları temizle
    Serial.print("Gelen Veri: ");
    Serial.println(receivedData);

    int commaIndex = receivedData.indexOf(',');
    
    if (commaIndex != -1) {
      String prefix = receivedData.substring(0, commaIndex);
      String value = receivedData.substring(commaIndex + 1);
      
      String commandValue = value; 
      commandValue.toLowerCase(); // Büyük/küçük harf hatasını önle

      // --- M: MOTOR KOMUTLARI ---
      if (prefix == "M") { 
        setLineText(1, "Hareket: " + value); 
        
        if (commandValue == "ileri") {
          stopMotors();
          moveForward();
        } 
        else if (commandValue == "geri"){
          stopMotors();
          moveBackward();
        } 
        else if (commandValue == "sol"){
          stopMotors();
          turnLeft();
        } 
        else if (commandValue == "sag" || commandValue == "sağ") { 
          stopMotors();
          turnRight();
        }
        else if (commandValue == "dur") {
          stopMotors();
          motorRunning = false;
        }
      } 
      
      // --- C: SOHBET (LCD) ---
      else if (prefix == "C") { 
        // Türkçe karakter düzeltmesi (LCD'de bozuk görünmesin diye)
        value.replace("ğ", "g"); value.replace("Ğ", "G");
        value.replace("ş", "s"); value.replace("Ş", "S");
        value.replace("ı", "i"); value.replace("İ", "I");
        value.replace("ç", "c"); value.replace("Ç", "C");
        value.replace("ü", "u"); value.replace("Ü", "U");
        value.replace("ö", "o"); value.replace("Ö", "O");
        
        setLineText(0, value); // Üst satıra yaz
      } 
      
      // --- T: TEST ---
      else if (prefix == "T") { 
        setLineText(1, "Baglanti: OK"); 
        Serial1.println("Arduino: Mesaj alindi\n");
      }
    }

    receivedData = ""; // Temizle
    newData = false;   
  }

  // Ekranı güncelle
  updateScrollingDisplay();
}

// =============================
// LCD KAYAN YAZI FONKSIYONLARI
// =============================
void setLineText(int line, String text) {
  String paddedText = text + "   "; 
  if (line == 0) {
    line1 = paddedText;
    scrollIndex1 = 0; 
  } else if (line == 1) {
    line2 = paddedText;
    scrollIndex2 = 0; 
  }
}

void startMotorWithTimeout(unsigned long durationMs) {
  motorStartTime = millis();
  motorDuration = durationMs;
  motorRunning = true;
}

void updateScrollingDisplay() {
  if (millis() - lastScrollTime < scrollDelay) return;
  lastScrollTime = millis();

  // --- Satır 1 ---
  lcd.setCursor(0, 0);
  if (line1.length() <= 16) {
    lcd.print(line1);
    for (int i = line1.length(); i < 16; i++) lcd.print(" ");
  } else {
    String scrollText1 = line1 + line1.substring(0, 16); 
    String displayLine1 = scrollText1.substring(scrollIndex1, scrollIndex1 + 16);
    lcd.print(displayLine1);
    scrollIndex1++;
    if (scrollIndex1 >= line1.length()) scrollIndex1 = 0;
  }

  // --- Satır 2 ---
  lcd.setCursor(0, 1);
  if (line2.length() <= 16) {
    lcd.print(line2);
    for (int i = line2.length(); i < 16; i++) lcd.print(" ");
  } else {
    String scrollText2 = line2 + line2.substring(0, 16);
    String displayLine2 = scrollText2.substring(scrollIndex2, scrollIndex2 + 16);
    lcd.print(displayLine2);
    scrollIndex2++;
    if (scrollIndex2 >= line2.length()) scrollIndex2 = 0;
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

  startMotorWithTimeout(1500); // 1.5 saniye
}

void moveBackward() {
  analogWrite(ENA, motorSpeed);
  analogWrite(ENB, motorSpeed);
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, HIGH);
  digitalWrite(motor2Pin1, HIGH);
  digitalWrite(motor2Pin2, LOW);

  startMotorWithTimeout(1500); // 1.5 saniye
}

void turnLeft() {
  analogWrite(ENA, motorSpeed);  // Sol motor yavaş
  analogWrite(ENB, motorSpeed);      // Sağ motor hızlı
  digitalWrite(motor1Pin1, HIGH);
  digitalWrite(motor1Pin2, LOW);
  digitalWrite(motor2Pin1, HIGH);
  digitalWrite(motor2Pin2, LOW);

  startMotorWithTimeout(500); // 0.5 saniye
}

void turnRight() {
  analogWrite(ENA, motorSpeed);      // Sol motor hızlı
  analogWrite(ENB, motorSpeed);  // Sağ motor yavaş
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, HIGH);
  digitalWrite(motor2Pin1, LOW);
  digitalWrite(motor2Pin2, HIGH);

  startMotorWithTimeout(500); // 0.5 saniye
}

void stopMotors() {
  analogWrite(ENA, 0);
  analogWrite(ENB, 0);
  digitalWrite(motor1Pin1, LOW);
  digitalWrite(motor1Pin2, LOW);
  digitalWrite(motor2Pin1, LOW);
  digitalWrite(motor2Pin2, LOW);

  motorRunning = false;
}
