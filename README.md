# Klasifikasi Ekspresi Wajah

Aplikasi mobile Flutter untuk mendeteksi dan mengklasifikasikan ekspresi wajah secara **real-time** menggunakan kamera smartphone dan model **TensorFlow Lite** yang dilatih melalui [Teachable Machine](https://teachablemachine.withgoogle.com/).

## Tujuan Aplikasi

Aplikasi ini memanfaatkan kamera (depan atau belakang) untuk mengenali 4 jenis ekspresi wajah secara langsung:

| Kode | Ekspresi | Emoji |
|------|----------|-------|
| 0 | Marah | 😠 |
| 1 | Sedih | 😢 |
| 2 | Netral | 😐 |
| 3 | Senang | 😊 |

## Teknologi yang Digunakan

| Teknologi | Kegunaan |
|-----------|----------|
| [Flutter](https://flutter.dev/) | Framework UI cross-platform |
| [TensorFlow Lite](https://www.tensorflow.org/lite) | Runtime model machine learning di perangkat mobile |
| [tflite_flutter](https://pub.dev/packages/tflite_flutter) `^0.12.1` | Plugin Flutter untuk menjalankan model TFLite |
| [camera](https://pub.dev/packages/camera) `^0.10.0` | Akses kamera perangkat dan streaming frame |
| [image](https://pub.dev/packages/image) `^4.0.0` | Preprocessing gambar (resize, konversi format) |
| [Teachable Machine](https://teachablemachine.withgoogle.com/) | Platform untuk melatih model klasifikasi gambar |

## 🔧 Cara Kerja (Alur Proses)

```
┌──────────────┐
│  Kamera      │  Frame dari kamera (YUV420 / BGRA)
└──────┬───────┘
       ▼
┌──────────────┐
│  Konversi    │  YUV420 → RGB (per-pixel color space conversion)
└──────┬───────┘
       ▼
┌──────────────┐
│  Resize      │  Ubah ukuran gambar ke 224 x 224 pixel
└──────┬───────┘
       ▼
┌──────────────┐
│  Normalisasi │  Skala pixel dari [0-255] ke [0.0-1.0] (Float32)
└──────┬───────┘
       ▼
┌──────────────┐
│  Inferensi   │  Jalankan model TFLite → output probabilitas 4 kelas
└──────┬───────┘
       ▼
┌──────────────┐
│  Hasil       │  Ambil kelas dengan probabilitas tertinggi
└──────┬───────┘
       ▼
┌──────────────┐
│  UI Overlay  │  Tampilkan emoji + label + confidence %
└──────────────┘
```

### Detail Teknis

- **Input Model**: Tensor `[1, 224, 224, 3]` — 1 gambar, 224x224 pixel, 3 channel RGB
- **Output Model**: Tensor `[1, 4]` — probabilitas untuk masing-masing 4 ekspresi
- **Normalisasi**: Pixel dinormalisasi ke rentang `[0.0, 1.0]` (standar model unquant Teachable Machine)
- **Rotasi**: Frame kamera dirotasi berdasarkan `sensorOrientation` perangkat agar sesuai orientasi portrait
- **Throttling**: Maksimal ~5 FPS inferensi (delay 200ms antar frame) untuk menjaga performa UI tetap smooth

## 🚀 Instalasi & Menjalankan

### Prasyarat

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versi terbaru)
- Android SDK dengan API level 21+
- Perangkat Android fisik (kamera tidak tersedia di emulator)

### Langkah-langkah

1. **Clone repository**
   ```bash
   git clone <repository-url>
   cd klasifikasi_ekspresi
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Jalankan di device**
   ```bash
   flutter run
   ```

4. **Build APK (opsional)**
   ```bash
   flutter build apk --release
   ```

> **Penting**: Aplikasi ini harus dijalankan di **perangkat fisik Android** karena memerlukan akses kamera dan akselerasi hardware untuk TFLite.

## 📱 Cara Penggunaan

1. **Buka aplikasi** — Kamera akan otomatis aktif (kamera depan sebagai default)
2. **Tekan tombol ▶️ (Play)** — Untuk memulai deteksi ekspresi wajah
3. **Arahkan kamera ke wajah** — Hasil prediksi akan muncul di overlay bawah layar
4. **Tekan tombol 🔄 (Switch)** — Untuk berganti antara kamera depan dan belakang
5. **Tekan tombol ⏹️ (Stop)** — Untuk menghentikan deteksi

## 🧠 Tentang Model

Model yang digunakan adalah **model_unquant.tflite** yang dilatih menggunakan [Google Teachable Machine](https://teachablemachine.withgoogle.com/):

- **Tipe**: Image Classification (Klasifikasi Gambar)
- **Format**: TensorFlow Lite (unquantized / float32)
- **Input Size**: 224 × 224 × 3 (RGB)
- **Output**: 4 kelas ekspresi wajah
- **Training Platform**: Teachable Machine (transfer learning berbasis MobileNet)

### Melatih Ulang Model

Jika ingin melatih ulang model dengan data sendiri:

1. Buka [Teachable Machine](https://teachablemachine.withgoogle.com/)
2. Pilih **Image Project**
3. Buat 4 kelas sesuai label (`marah`, `sedih`, `netral`, `senang`)
4. Upload/ambil sampel gambar untuk setiap kelas
5. Klik **Train Model**
6. Export sebagai **TensorFlow Lite** (pilih format floating point / unquantized)
7. Ganti file `assets/model_unquant.tflite` dengan model baru
8. Pastikan urutan label di `assets/labels.txt` sesuai dengan kelas saat training

> Catatan: Versi saat ini menggunakan 4 kelas: `marah`, `sedih`, `netral`, `senang` (sesuai `assets/labels.txt`).

## 📄 Konfigurasi Android

Konfigurasi penting yang sudah diterapkan:

- **`minSdkVersion: 21`** — Diperlukan oleh camera package
- **`aaptOptions { noCompress += "tflite" }`** — Agar file model tidak dikompresi saat build
- **Permission `CAMERA`** — Izin akses kamera di AndroidManifest.xml

## 📝 Lisensi

Proyek ini dibuat untuk keperluan pembelajaran dan penelitian.
