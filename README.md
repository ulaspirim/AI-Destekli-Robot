# PROJE ADI: AI Destekli Otonom Robot

## Proje Tanımı

Bu proje, **bilgisayar mühendisliği bitirme projesi** kapsamında geliştirdiğim, **yapay zeka destekli, otonom hareket edebilen ve insanlarla doğal etkileşim kurabilen bir robot sistemidir**. Robot; çevresini algılayabilen, insan ve nesne tanıma yapabilen, öğrenme yeteneğine sahip ve sesli iletişim kurabilen bir yapıdadır.

Projenin temel amacı, **robotik sistemler ile yapay zekayı entegre ederek gerçek dünyada kullanılabilir, ölçeklenebilir ve akıllı bir etkileşimli robot prototipi geliştirmektir**.

Robot, karar verme süreçlerini büyük ölçüde yapay zeka modelleri (Vertex AI ve Gemini) üzerinden yürütürken; donanımsal hareketler Arduino tabanlı bir kontrol sistemi ile gerçekleştirilmektedir.

---

## Proje Kategorisi

* Yapay Zeka Destekli Robotik Sistemler
* İnsan–Robot Etkileşimi (HRI)

---

## Proje Ekibi

* **Geliştirici:** Ulaş PİRİM

---

## Proje Amacı ve Hedefler

* Yapay zeka destekli karar verebilen bir robot geliştirmek
* İnsanlarla doğal dil kullanarak etkileşim kurabilen bir sistem oluşturmak
* Görüntü işleme ile insan ve nesne algılama sağlamak
* Otonom hareket ve yönelim kabiliyeti kazandırmak
* Mobil uygulama üzerinden robot kontrolü ve izleme sağlamak

---

# SİSTEM MİMARİSİ

## Genel Mimari

Sistem üç ana bileşenden oluşmaktadır:

1. **Mobil Uygulama (Flutter)**
2. **Yapay Zeka & Bulut Servisleri (Google Cloud Platform)**
3. **Donanım Katmanı (Arduino Tabanlı Robot)**

Mobil uygulama, yapay zekâ karar mekanizmasının merkezinde yer almakta ve robotun tüm hareket kararları bu katman üzerinden iletilmektedir.

---

## Kullanılan Donanımlar

* Arduino Mega 2560
* DC motorlar / motor sürücüleri
* LCD ekran
* HC-05
* 4 Adet 18650 Lityum Pil

---

## Kullanılan Yazılımlar ve Teknolojiler

### Mobil ve Uygulama Katmanı

* **Flutter** – Mobil uygulama geliştirme
* **Dart** – Uygulama programlama dili

### Yapay Zeka ve Bulut

* **Google Cloud Platform**
* **Vision API** – Görüntü işleme ve nesne tanıma
* **Speech-to-Text** – Ses algılama
* **Text-to-Speech** – Robotun konuşması
* **Dialogflow / Gemini AI** – Doğal dil işleme ve karar verme
* **TensorFlow Lite** – Cihaz üzerinde çalışan AI modelleri
* **Firebase** - Yüzlerin veri tabanına kaydedilmesi

### Donanım

* **Arduino C++** – Robot kontrol yazılımı
* **HC-05 Bluetooth** – Mobil uygulama ve Arduino haberleşmesi

---

# GEREKSİNİM ANALİZİ

## Fonksiyonel Gereksinimler

* Robotun otonom hareket edebilmesi
* Engel algılama ve kaçınma
* İnsan yüzü algılama ve takip etme
* Sesli komutları algılama
* Doğal dil ile sohbet edebilme
* Mobil uygulama üzerinden kontrol
* Sensör verilerinin gerçek zamanlı işlenmesi

## Fonksiyonel Olmayan Gereksinimler

* Gerçek zamanlı tepki süresi
* Düşük gecikmeli iletişim
* Modüler ve genişletilebilir yapı
* Enerji verimliliği

---

# KİŞİSEL GEREKSİNİM ANALİZİ (Ulaş PİRİM)

1. **Otonom Hareket Sistemi**
   Robotun çevresel verilere göre kendi hareket kararlarını verebilmesi.

2. **Görüntü İşleme**
   Kamera üzerinden insan ve nesne algılama yapılması.

3. **Yüz Takibi**
   Algılanan insan yüzüne doğru robotun yönelmesi.

4. **Sesli Etkileşim**
   Robotun kullanıcı ile doğal konuşma yapabilmesi.

5. **Mobil Uygulama Entegrasyonu**
   Flutter tabanlı mobil uygulama üzerinden robotun izlenmesi ve kontrol edilmesi.

6. **Yapay Zeka Karar Mekanizması**
   Robotun davranışlarının büyük ölçüde AI destekli karar sistemiyle yönetilmesi.

---

# PROJE SÜREÇLERİ

* Gereksinim Analizi
* Sistem Mimarisi Tasarımı
* Donanım Kurulumu
* Yazılım Geliştirme
* Yapay Zeka Model Entegrasyonu
* Test ve Doğrulama
* Dokümantasyon

---

## Sonuç

Bu proje, yapay zeka ile robotik sistemlerin bütünleşik çalışmasını hedefleyen, gerçek dünya senaryolarına uygulanabilir bir **akıllı robot prototipi** ortaya koymayı amaçlamaktadır.

<img width="1600" height="171" alt="image" src="https://github.com/user-attachments/assets/acd3e40c-9535-4c88-a0bf-cd328283fd50" />

