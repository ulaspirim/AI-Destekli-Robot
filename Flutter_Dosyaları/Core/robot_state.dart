enum RobotState {
  idle,           // Bekliyor
  searching,      // Otonom gezme (Devriye)
  personDetected, // İnsan algılandı (ML Kit)
  interacting,    // Tanıma + Sohbet aşaması
  exploring,      // (Opsiyonel) Etrafı gezme
  humanDetected,  // (Eşanlamlı - kodda bunu kullandık)
  chatting,       // Sohbet modu
  registeringFace, // Yüz kaydetme modu
}