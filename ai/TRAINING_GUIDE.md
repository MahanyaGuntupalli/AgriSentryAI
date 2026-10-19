# Training the AgriSentry Disease Model (Phase 5)

Goal: replace the `PLACEHOLDER_SIMULATED` unavailable result with real,
validated `TRAINED` predictions. Until that happens, the backend returns
`NO_RELIABLE_DISEASE` and does not invent a disease. Nothing in the backend or app changes —
the backend detects `ai/models/tomato_disease_model.h5` automatically.

> **Multi-crop roadmap:** this guide trains the TOMATO disease model
> (Stage 2). For Stage-1 crop identification (Tomato/Rice/Cotton/Chilli/Maize
> + not-a-plant) and the other crops' disease models, see
> [`DATASET_PLAN.md`](DATASET_PLAN.md) and `dataset/download_crops.py`.
> A deployed Stage-1 model = `ai/models/crop_model.h5` +
> `ai/models/crop_model_labels.txt`; `/api/health` then reports
> `crop_identification: TRAINED` and `/api/analyze` fills the `plant` field
> with a real identification instead of UNKNOWN.

```
dataset (4 tomato classes)  →  train.py  →  ai/models/tomato_disease_model.h5
                                                   ↓  (auto-detected)
                              backend /api/analyze  →  model_status = "TRAINED"
```

## Step 0 — Install the training tools

Use the backend venv (already has numpy + Pillow):

```bash
cd Zip2/AgriSentryAI/backend
.venv/Scripts/activate          # Windows  (Linux/Mac: source .venv/bin/activate)
pip install "tensorflow>=2.15" kagglehub
```

No GPU needed — MobileNetV2 transfer learning trains in ~30-60 min on a
normal laptop CPU (or free on Google Colab with a T4 GPU).

## Step 1 — Download the PlantVillage tomato subset

```bash
cd Zip2/AgriSentryAI/ai
python dataset/download_plantvillage.py
```

This builds `ai/dataset/tomato/` with exactly the four classes train.py
expects. It tries, in order:

1. **Kaggle (recommended)** — needs a one-time free token:
   - kaggle.com → Account → Create New Token (downloads `kaggle.json`)
   - put it in `C:\Users\<you>\.kaggle\kaggle.json`
   - rerun the script (uses `abdallahalidev/plantvillage-dataset`)
2. **Git fallback, no account** — `--git` clones a public mirror (~250 MB)
3. **Already downloaded manually?** — `--source <your-folder>`; the script
   finds the `Tomato___*` folders anywhere under it

Expected result (~7.4k images):

```
dataset/tomato/
  Healthy/            ~1,591
  Early Blight/       ~1,000
  Late Blight/        ~1,903
  Bacterial Spot/     ~2,127
```

## Step 2 — Train

```bash
cd Zip2/AgriSentryAI/ai/training
python train.py --dataset_dir ../dataset/tomato --epochs 12 --batch_size 32
```

What it does automatically:
- MobileNetV2 (ImageNet weights) + new classification head
- Phase 1: frozen base, 12 epochs · Phase 2: fine-tunes the top 30 layers
- saves the best checkpoint to `ai/models/tomato_disease_model.h5`
- rewrites `ai/models/labels.txt` from the class folders

Aim for **val_accuracy ≥ 0.95** (PlantVillage is easy for transfer learning).

⚠️ Keep the class folder names EXACTLY as the downloader creates them —
they become `labels.txt`, which the backend and app rely on.

## Step 3 — Restart the backend and verify

```bash
cd Zip2/AgriSentryAI/backend
python -m uvicorn app.main:app --reload --port 8000
```

The model is found automatically (`ai/models/` next to the backend) and
`TensorFlow` loads on startup (now in `backend/requirements.txt`).

```bash
python integration/api_tests/test_api.py
# ... model_status=TRAINED ... ALL TESTS PASSED
```

Or check the app: scan a leaf → the SIMULATED banner is gone, and
`/api/analyze` reports `"model_status": "TRAINED"`.

## Step 4 — Reality check the model (2 min)

PlantVillage photos are studio-like; phone photos are not. Before trusting
it in a demo, scan 3-4 real leaves (or photos of leaves from your phone):

- works well → done
- overconfident/wrong → quick wins:
  - train with more augmentation (already on: rotation/shift/zoom/flip/brightness)
  - or fine-tune the whole base instead of the top 30 layers
  - or add a few hundred real field photos per class if you have them

## Troubleshooting

| Symptom | Fix |
|---|---|
| `dataset directory not found` | run the downloader from `ai/`, or pass `--dataset_dir ../dataset/tomato` |
| `Zip failure` / download stalls | use `--git`, or download the Kaggle zip manually and `--source` it |
| download says "already populated" | `dataset/tomato` exists — delete it to rebuild |
| OOM / crash during training | lower `--batch_size 16` (or 8) |
| training is very slow | that's CPU life; Colab GPU is the free fix |
| backend still shows `PLACEHOLDER_SIMULATED` | model file must be exactly `ai/models/tomato_disease_model.h5`, and uvicorn must be restarted |
| 500 on /api/analyze with model present | usually a TF version mismatch — re-save the model with the same TF as the backend (`pip show tensorflow`) |
