# ShutterBridge — Windows + iPhone, Mac ke baghair

## 1. Downloads

[Latest release](https://github.com/msaadatmustafa-tech/ShutterBridge/releases/latest) se Windows EXE aur **unsigned** iPhone IPA download karein. Source ZIP bhi available hai. Agar apna iPhone build banana hai to repository fork karein → Actions enable karein → **Build iPhone IPA (no Mac required) → Run workflow** → successful run se IPA artifact download/extract karein.

## 2. iPhone app install karein

1. [Official Sideloadly](https://sideloadly.io/) install karein aur uski Windows driver/dependency instructions follow karein.
2. iPhone USB se connect, unlock aur **Trust This Computer** accept karein.
3. Sideloadly mein iPhone aur downloaded unsigned IPA select karein.
4. Apni Apple ID aur authentication sirf local installer mein enter karein. Password, signing key aur provisioning profile kabhi GitHub par upload na karein.
5. Install ke baad agar iPhone trust/developer-mode prompt de to usay phone par complete karein. Signing expire hone par local installer se refresh karna par sakta hai; [official FAQ](https://sideloadly.io/faq) dekhein.
6. **iPhone BLE Camera** kholein. Camera/Bluetooth allow karein. Audio ke liye Microphone aur Gallery save ke liye Add Photos allow karein. App foreground mein aur phone unlocked rakhein.

Update se pehle Files se recordings ka backup lein. Same Apple ID aur bundle ID se existing app par update karein.

## 3. Windows remote connect karein

1. Downloaded EXE kholein. Source use karna ho to Python 3.11+ with Tkinter install karke `Windows/START_WINDOWS.bat` chalayein.
2. Dono devices par Bluetooth on → **Scan for iPhone** → `iPhoneCam` → phone ka six-digit PIN → **Connect**.
3. Recording stopped ho to quality choose → **Apply quality** → confirmed dimensions/FPS check karein. Supported modes selected front/back camera par depend karte hain.
4. **Start** → **Stop & Save** → save complete hone dein. Video Photos/Gallery mein aur backup Files mein hogi.

## 4. Live preview aur Android

Same trusted Wi-Fi par iPhone mein **Enable Wi-Fi preview** on karein aur Local Network allow karein. Windows **LIVE PREVIEW** mein poora link paste karke Connect preview karein. Native desktop buttons ke liye Bluetooth connect hona zaroori hai.

Android ke liye **Allow Wi-Fi remote controls** on karein, iPhone ka QR scan karein aur Chrome mein page kholein. Android APK ki zaroorat nahi. [Detailed Wi-Fi guide](WIFI_ANDROID_SETUP.md).

## Yaad rakhein

- Bluetooth par video nahi jaati; original clip iPhone par record hoti hai.
- Preview ki quality kam hai; saved recording quality ka confirmed status alag hai.
- App ka duration timer cutoff nahi; storage, temperature, battery aur iOS interruptions limits hain.
- Foreground/unlocked operation required. Background/lock se capture band hoti hai.
- Live link aur PIN private rakhein. Wi-Fi preview Off se link revoke hota hai.

Real hardware test results: [Verification](VERIFICATION_AND_INSTALL.md).
