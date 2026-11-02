# Windows + iPhone — Mac ke baghair installation

**Aapko chahiye:** Windows 10/11 laptop, iPhone (iOS 16+), USB cable, GitHub account, Apple ID, aur Windows Bluetooth LE. Recording controller **local Bluetooth** par chalega. Sirf app ka initial build GitHub cloud par hoga. Apple ID ko GitHub par **kabhi upload mat karein**.

## Step 1: iPhone app ko GitHub par build karein

1. Download ZIP, **Extract All**.
2. Windows par [GitHub Desktop](https://desktop.github.com/) install karke GitHub mein sign in karein.
3. GitHub Desktop: **File > Add local repository** se extracted `iPhone-BLE-Camera-Remote` folder select karein. Agar ye Git repository nahi hai, **create a repository here** choose karein (ya File > New repository karke contents us mein copy karein).
4. Saari files including hidden `.github/workflows/build-ios-ipa.yml` commit karein. GitHub Desktop mein **Publish repository** click karein. **Keep this code private** select kar sakte hain (private GitHub Actions minutes par account usage/billing limits apply ho sakte hain).
5. GitHub website par apni repository open karein. **Actions > Build iPhone IPA (no Mac required) > Run workflow** click karein. `main` branch choose karein.
6. Build green/successful ho jaye, run open karein, neeche **Artifacts > iPhoneBLECamera-unsigned-IPA** se ZIP download karein.
7. Download ki hui artifact ZIP extract karein. Andar `iPhoneBLECamera-unsigned.ipa` milegi. **Yeh unsigned hai: direct iPhone par nahi chalegi.**

**Agar GitHub Actions mein workflow nazar nahi aaye:** check karein `.github/workflows/build-ios-ipa.yml` repository mein commit hui hai, default branch `main` hai, aur Actions enabled hain.

**Agar build fail ho:** Action run ke red failed step par click karke error dekhein. Native iOS build yahan test nahi hua, isliye project mein device/Xcode-specific fixes zaroori ho sakte hain.

## Step 2: Windows se iPhone mein IPA install karein

1. Official website: [Sideloadly](https://sideloadly.io/). Windows version download/install karein. Sideloadly ki Windows requirements follow karein (website ke mutabiq web-version iTunes/iCloud ki zaroorat ho sakti hai).
2. iPhone ko USB cable se Windows laptop se connect karein. Phone unlock karke **Trust This Computer** allow karein.
3. Sideloadly mein iPhone select karein aur `iPhoneBLECamera-unsigned.ipa` drop karein.
4. **Apni Apple ID sirf installer ki local app mein dein; na humein, na GitHub repo/workflow mein.** Signing/installation complete karein.
5. Agar prompt aaye, iPhone **Settings > Privacy & Security > Developer Mode** ON karein aur restart/confirmation complete karein.
6. Agar *Untrusted Developer* aaye, **Settings > General > VPN & Device Management** mein developer app trust karein (menus iOS version ke hisab se differ kar sakte hain).
7. iPhone par **iPhone BLE Camera** app open karein. Camera, microphone, Bluetooth permissions allow karein. Screen par 6-digit PIN show hoga.

**Free Apple ID limitation:** Personal signing normally **7 din** valid hoti hai; Sideloadly se refresh/reinstall karna hoga. Free accounts par simultaneous sideloaded-app limit bhi lag sakti hai. Ye recording ki duration limit nahi hai. App use karne ke liye jailbreak zaroori nahi.

## Step 3: Laptop se record karein

1. Windows folder mein `START_WINDOWS.bat` double-click karein. Agar Python missing hai to [python.org](https://www.python.org/downloads/windows/) se Python install karein.
2. iPhone app **foreground mein aur phone unlocked** rakhein. Dono devices par Bluetooth on ho.
3. Laptop controller > **Scan for iPhone** > `iPhoneCam` choose karein > iPhone ka 6-digit PIN enter karein > **Connect**.
4. 4K30 / 4K60 / 1080P30 / 1080P60 etc. select karein aur **Apply Quality** click karein. Mode tabhi chalega jab iPhone camera usay support kare.
5. **START RECORDING** aur baad mein **STOP RECORDING**. Video iPhone Files app / app Documents mein save hogi; zaroorat par USB se laptop par copy karein.

### Zaroori limitations

- **Bluetooth par 4K live laptop preview nahin hai.** Bluetooth sirf commands ke liye; original 4K clip iPhone par locally record hogi.
- **Unlimited ka matlab app mein clip ki fixed time limit nahi.** Storage, iPhone temperature/battery, permissions aur iOS interruption recording ko stop kar sakte hain.
- Bluetooth control ke liye internet nahi chahiye. GitHub Actions build aur first-time Windows dependency installation ke liye internet chahiye.
- Native iOS project ka code available hai magar **is package ko physical iPhone par abhi test nahi kiya gaya**, aur `.ipa` already generated ya signed nahi hai.

## Verified sources

- GitHub macOS runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Downloading GitHub Actions artifacts: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts
- Sideloadly download: https://sideloadly.io/
- Sideloadly free Apple ID FAQ: https://sideloadly.io/faq
