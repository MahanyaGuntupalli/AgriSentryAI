# AgriSentry AI — Multi-Crop Dataset & Training Plan

**Goal:** real Stage-1 crop identification (Tomato / Rice / Cotton / Chilli /
Maize + "not a plant") followed by per-crop Stage-2 disease detection, with
honest confidence values and class names that match the backend contract.

**Why datasets first:** as the pipeline audit showed, database records of
crops give the app *text*, not *vision*. Crop identification needs a trained
model, and a model needs labeled images. This document picks those images.

---

## Stage 1 — Crop-identification model (the missing capability)

**Output contract:** softmax over 6 classes, saved as
`ai/models/crop_model.h5` + `ai/models/crop_model_labels.txt`
(index-aligned, one class per line — exactly what
`backend/app/services/plant_inference.py` loads).

| # | Class | Purpose |
|---|-------|---------|
| 0 | `Tomato` | supported crop |
| 1 | `Rice` | supported crop |
| 2 | `Cotton` | supported crop |
| 3 | `Chilli` | supported crop |
| 4 | `Maize` | supported crop |
| 5 | `Unknown` | **not-a-plant / other plants / background** — rejects humans, animals, objects, random photos |

**Sources (verified on Kaggle, Sept 2026):**

| Crop | Dataset | Images | Notes |
|---|---|---|---|
| Tomato | `abdallahalidev/plantvillage-dataset` (Tomato___* folders) | ~19k total; sample 1–2k per class | also reused for Stage-2 tomato |
| Rice | `nirmalsankalana/rice-leaf-disease-image` | 5,932 (4 disease classes) | healthy rice leaves are scarce here — supplement from `anshulm257/rice-disease-dataset` (3,829 imgs incl. healthy) |
| Cotton | `seroshkarim/cotton-leaf-disease-dataset` | 1,710 (4 classes incl. healthy, field photos) | small but real-world; balance with augmentation |
| Chilli | `crewsat/chili-leaf-disease-image-dataset` | ~4,400 (Curl / Healthy / Spot / Whitefly / Yellowish) | field photos |
| Maize | `smaranjitghose/corn-or-maize-leaf-disease-dataset` | 4,188 (Common Rust / GLS / Blight / Healthy) | |
| Unknown | `dantez сооруж/plantdoc`-style negatives + non-plant photos | target ≥ 1,000 | any other PlantVillage crops (potato, grape, apple…) + everyday objects; PlantVillage's other-crop folders are ideal "other plants" negatives |

**Per-class floor:** ≥ 800 images (augmentation may supplement, but at least
half of each class should be real photos). Cotton is the thinnest class —
monitor its per-class validation accuracy separately.

**Training recipe:** reuse `ai/training/train.py` (MobileNetV2 transfer
learning, 224×224, /255 rescale) with `--dataset_dir dataset/crops/`.
Expected result on CPU: ~30–45 min; target val_accuracy ≥ 0.90 overall and
≥ 0.80 for `Unknown`.

**Export for on-device (optional Phase 2):** `tf.lite.TFLiteConverter` →
`mobile_assets/crop_model.tflite` — the Flutter `PlantDiseaseEngine`
interface already exists for drop-in.

---

## Stage 2 — Per-crop disease models

Class names here become `labels.txt`; the backend's crop-consistency gate
(`_disease_class_matches_crop`) accepts crop-neutral names (Healthy, Early
Blight…) and rejects classes naming a different crop, so keep names clean of
crop prefixes OR include them consistently.

| Crop | Dataset | Classes (→ labels.txt) |
|---|---|---|
| **Tomato** | PlantVillage subset (already scripted: `ai/dataset/download_plantvillage.py`) | `Healthy`, `Early Blight`, `Late Blight`, `Bacterial Spot` — optionally extend with `Leaf Mold`, `Septoria Leaf Spot`, `Target Spot`, `Mosaic Virus`, `Yellow Leaf Curl Virus`, `Spider Mites` to match the app knowledge base (14 entries today) |
| **Rice** | `nirmalsankalana/rice-leaf-disease-image` + `anshulm257/rice-disease-dataset` | `Healthy`, `Bacterial Leaf Blight`, `Leaf Blast`, `Brown Spot`, `Tungro` |
| **Cotton** | `seroshkarim/cotton-leaf-disease-dataset` | `Healthy`, `Bacterial Blight`, `Fungal Leaf Disease`, `Aphid Damage`, `Army Worm Damage` |
| **Chilli** | `crewsat/chili-leaf-disease-image-dataset` | `Healthy`, `Leaf Curl`, `Leaf Spot`, `Whitefly Damage`, `Yellowish` |
| **Maize** | `smaranjitghose/corn-or-maize-leaf-disease-dataset` | `Healthy`, `Common Rust`, `Gray Leaf Spot`, `Northern Leaf Blight` |

Deployment per crop: `ai/models/disease_<crop>.h5` + `disease_<crop>_labels.txt`;
`disease_inference.py` selects the file by the Stage-1 identified crop
(extend `_model_for_crop()` when adding crops — the tomato default stays).

---

## Execution order (matches the approved 4-part plan)

1. **Now:** train the existing tomato 4-class model (download already running)
   → backend flips to `model_status: TRAINED` with zero further code changes.
2. Build `dataset/crops/` for Stage 1 (scripts below), train, deploy
   `crop_model.h5` + `crop_model_labels.txt`.
3. Train rice/cotton/chilli/maize Stage-2 models; add per-crop routing in
   `disease_inference.py`.
4. Field-validate: PlantVillage-style photos are clean; real phone photos
   need a few hundred local samples per class to stay honest.

## Helper script to add

`ai/dataset/download_crops.py` (kagglehub-based, mirrors
`download_plantvillage.py`): downloads the five datasets above, renames
folders to the canonical class names, enforces the ≥800-per-class floor,
and writes `dataset/crops/<Class>/`. Kaggle token required (free).
