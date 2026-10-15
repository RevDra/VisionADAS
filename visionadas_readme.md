# VisionADAS 🚗📱✨

**VisionADAS** is an open-source, next-generation Advanced Driver Assistance System (ADAS) built natively for iOS. Leveraging modern computer vision, CoreML/YOLO vehicle tracking, dynamic lane detection, and augmented reality (AR) HUD overlays, VisionADAS transforms your iPhone into a smart driving companion.

---

## 🚀 Key Features

* **Real-Time Vehicle Detection:** Powered by optimized YOLO models to detect cars, trucks, and buses ahead with bounding boxes and headway distance estimation.
* **Computer Vision Lane Detection:** Advanced zero-copy grayscale ingestion from camera buffers using adaptive thresholding, sliding windows, and 2nd-degree polynomial curve fitting ($x = a \cdot y^2 + b \cdot y + c$) for robust highway tracking.
* **AR Electric Neon Road Carpet:** High-visibility Neon Green (`#00FF5A`) perspective-correct mesh that clings dynamically to actual road lane boundaries and stops cleanly at lead vehicle tires.
* **Online Dynamic Calibration:** Automatically adapts the vanishing point and horizontal yaw offset based on vehicle trajectories and camera mounting positions.
* **Multi-Tier Safety Alerts:** Intelligent visual warnings (Safe, Caution, Danger states) based on time-headway calculations.

---

## 🛠 Tech Stack & Architecture

* **Language:** Swift 5.9+
* **UI Framework:** SwiftUI with custom Metal/CoreGraphics AR rendering layers.
* **Computer Vision:** Accelerate framework, Vision, CoreML, and custom image processing pipelines.
* **Project Management:** **XcodeGen** (`project.yml` driven architecture to prevent merge conflicts and `.xcodeproj` bloat).
* **CI/CD:** Automated GitHub Actions workflows for building, testing, and verifying build integrity.

---

## 📂 Project Structure

```text
VisionADAS/
├── App/                  # App entry point and lifecycle
├── Core/
│   ├── Vision/           # RealLaneDetector & YOLO integration
│   ├── Kinematics/       # OnlineCalibrator & physics calculations
│   └── Models/           # Data models (TrackedVehicle, DetectedLane, etc.)
├── UI/
│   ├── DashboardView.swift # Main container & HUD coordinator
│   └── ADASHUDView.swift   # AR lane carpet & metric overlays
├── project.yml           # XcodeGen configuration file
└── README.md
```

---

## ⚙️ Getting Started & Installation

Because VisionADAS uses **XcodeGen** to manage project structures, you do not need to commit `.xcodeproj` files. Follow these steps to set up the project locally:

### Prerequisites
* macOS with **Xcode 15+** installed.
* **Homebrew** package manager.

### Step 1: Clone the Repository
```bash
git clone https://github.com/your-username/VisionADAS.git
cd VisionADAS
```

### Step 2: Install XcodeGen
If you don't have XcodeGen installed on your Mac, install it via Homebrew:
```bash
brew install xcodegen
```

### Step 3: Generate the Xcode Project
Run XcodeGen in the root directory to generate the `.xcodeproj` file:
```bash
xcodegen generate
```

### Step 4: Open and Build
1. Open `VisionADAS.xcodeproj` in Xcode.
2. Select your development team under **Signing & Capabilities**.
3. Connect a physical iOS device (Camera and sensor-heavy features require a real device).
4. Press `Cmd + R` to build and run!

---

## 🤖 CI/CD & Build Stability

This repository includes a GitHub Actions workflow to ensure continuous integration. 
* To prevent build failures (`exit code 65`), always ensure that any code generated or updated matches the correct Swift syntax and that `project.yml` correctly references all source files before pushing.
* Run `xcodegen generate` locally after adding or removing files to keep the Xcode project in sync.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.