# Running AgriSentry AI in VS Code — step by step

## One-time setup (≈5 min)

1. **Open the project**
   - VS Code → `File → Open Workspace from File…`
   - pick `Zip2/AgriSentryAI/agrisentry.code-workspace`
   - When prompted for recommended extensions, click **Install** (Python, Flutter/Dart).

2. **Install Flutter** (skip if `flutter --version` already works in a terminal):
   - download the SDK zip → extract to e.g. `C:\src\flutter`
   - add `C:\src\flutter\bin` to your PATH
   - run `flutter doctor` and fix what it flags (Android Studio for the emulator, or just plug in a phone).

3. **Create the Python venv + install backend deps** (one click):
   - `Ctrl+Shift+P` → **Tasks: Run Task** → `START HERE: setup everything (1+2)`
   - or run the two tasks `1.` and `2.` individually.

## Run the whole system (3 terminals, or one click)

**Option A — one click:** open `Run and Debug` (`Ctrl+Shift+D`) → pick **🚀 Full system (backend + sensors + app)** → ▶️. It starts backend, sensor simulator and the Flutter app together.

**Option B — manually, terminal by terminal:**

| Terminal | Command (VS Code picks the venv automatically) |
|---|---|
| 1 — backend | `Ctrl+Shift+P` → Tasks → `3. Backend: run uvicorn (no debug)` |
| 2 — sensors | Tasks → `4. Sensor simulator` |
| 3 — app | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000` |

**Option C — with debugging:** Run and Debug → `⚙️ Backend: uvicorn (FastAPI)` to debug with breakpoints; then `📱 Flutter: Android emulator` for the app.

## Verify it's alive

- Open **http://localhost:8000/docs** — interactive API docs.
- Tasks → `5. API tests` → should end with `ALL TESTS PASSED`.
- In the app dashboard you should see live sensor values with a **SIMULATED** banner.

## Physical phone instead of emulator

- Use the launch config `📱 Flutter: physical phone` (edit `YOUR_PC_LAN_IP` in `.vscode/launch.json` first — `ipconfig` → IPv4 address), or run
  `flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_LAN_IP>:8000`.
- Backend must stay on `--host 0.0.0.0` (it already is).

## Where things live

| Folder | What it is |
|---|---|
| `backend/` | FastAPI + risk engine + SQLite |
| `mobile/` | Flutter app |
| `ai/` | training/inference code (drop `tomato_disease_model.h5` into `ai/models/` to go from placeholder → trained) |
| `integration/` | sensor simulator + API tests |
| `hardware/` | ESP32 firmware + wiring guide (Phase 1) |

## Troubleshooting

| Problem | Fix |
|---|---|
| `The token '&&' is not a valid statement separator` | fixed in `.vscode/tasks.json` — setup now chains tasks 1a→1b (works in PowerShell); reopen the workspace |
| `Could not find env file: backend/.env` when starting the backend debug config | fixed — the stale `envFile` entry was removed from `launch.json`; nothing to do |
| Setup task seems stuck installing huge packages | TensorFlow was removed from base requirements (it's ~500 MB); it now installs only via task `6. AI: install training tools` |
| `flutter: command not found` | PATH missing `...\flutter\bin`; restart VS Code after editing PATH |
| Backend task fails: no module uvicorn | run task `1.` again (venv not built) |
| App can't reach backend on emulator | use `10.0.2.2` (not `localhost`) — that's the emulator's alias for your PC |
| App can't reach backend on phone | use your PC's LAN IP, same Wi-Fi network, firewall allows 8000 |
| Port 8000 already in use | `netstat -ano \| findstr :8000` → `taskkill /PID <pid> /F` |
