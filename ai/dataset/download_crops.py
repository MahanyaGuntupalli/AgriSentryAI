#!/usr/bin/env python3
"""Build the STAGE-1 crop-identification dataset (see ai/DATASET_PLAN.md).

Creates next to this file:
    dataset/crops/
        Tomato/   Rice/   Cotton/   Chilli/   Maize/   Unknown/

Sources (Kaggle, free token required - see TRAINING_GUIDE.md Step 1):
    abdallahalidev/plantvillage-dataset      -> Tomato (Tomato___* folders)
    nirmalsankalana/rice-leaf-disease-image  -> Rice
    anshulm257/rice-disease-dataset          -> Rice (healthy supplement)
    seroshkarim/cotton-leaf-disease-dataset  -> Cotton
    crewsat/chili-leaf-disease-image-dataset -> Chilli
    smaranjitghose/corn-or-maize-leaf-disease-dataset -> Maize
    Any OTHER crop folders in a PlantVillage copy -> Unknown (not-a-plant)

Usage:
    python download_crops.py                 # auto (kagglehub, needs token)
    python download_crops.py --source D:/pv  # reuse a local PlantVillage copy
    python download_crops.py --skip kaggle   # only use --source

Per-class floor: MIN_PER_CLASS images (augmentation can top up later, but at
least half of each class should be real photos - see DATASET_PLAN.md).
"""
import argparse
import shutil
from pathlib import Path

AI_DIR = Path(__file__).resolve().parents[1]
OUT = AI_DIR / "dataset" / "crops"
MIN_PER_CLASS = 800

IMG_EXT = {".jpg", ".jpeg", ".png"}

KAGGLE_SLUGS = {
    "Rice": ["nirmalsankalana/rice-leaf-disease-image",
             "anshulm257/rice-disease-dataset"],
    "Cotton": ["seroshkarim/cotton-leaf-disease-dataset"],
    "Chilli": ["crewsat/chili-leaf-disease-image-dataset"],
    "Maize": ["smaranjitghose/corn-or-maize-leaf-disease-dataset"],
}

# Class-folder fragments -> canonical crop class
RICE_MARKERS = ("bacterial", "blast", "brown", "tungro", "healthy", "smut")
COTTON_MARKERS = ("aphid", "army", "bacterial", "fungal", "healthy", "powdery",
                  "target", "curl")
CHILLI_MARKERS = ("curl", "healthy", "spot", "whitefly", "yellowish")
MAIZE_MARKERS = ("rust", "gray", "blight", "healthy", "common")

CROP_MARKERS = {
    "Rice": RICE_MARKERS,
    "Cotton": COTTON_MARKERS,
    "Chilli": CHILLI_MARKERS,
    "Maize": MAIZE_MARKERS,
}


def count_images(folder: Path) -> int:
    if not folder.is_dir():
        return 0
    return sum(1 for p in folder.rglob("*") if p.suffix.lower() in IMG_EXT)


def link_or_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        return
    try:
        dst.hardlink_to(src)
    except OSError:
        shutil.copy2(src, dst)


def harvest_folder(src: Path, crop: str) -> int:
    """Copy every image under src into dataset/crops/<crop>/ (dedup by name)."""
    n = 0
    for img in src.rglob("*"):
        if img.suffix.lower() in IMG_EXT and img.is_file():
            dst = OUT / crop / img.name
            if not dst.exists():
                link_or_copy(img, dst)
                n += 1
    return n


def folder_matches_crop(folder_name: str, crop: str) -> bool:
    low = folder_name.lower()
    if crop == "Tomato":
        return low.startswith("tomato")
    return any(m in low for m in CROP_MARKERS[crop])


def organize_from(source_root: Path) -> None:
    """Harvest crop folders from a local tree (e.g. a PlantVillage copy)."""
    print(f"Harvesting crop folders under: {source_root}")
    for folder in source_root.rglob("*"):
        if not folder.is_dir():
            continue
        for crop in list(CROP_MARKERS) + ["Tomato"]:
            if folder.name.lower().startswith(("tomato",)) and crop == "Tomato" \
                    or crop != "Tomato" and folder_matches_crop(folder.name, crop):
                n = harvest_folder(folder, crop)
                if n:
                    print(f"  {crop}: +{n} from '{folder.name}'")
                break


def harvest_unknown_from(source_root: Path) -> None:
    """Any PlantVillage folder that is NOT one of our five crops -> Unknown."""
    for folder in source_root.rglob("*"):
        if not folder.is_dir():
            continue
        low = folder.name.lower()
        if any(low.startswith(c) for c in
               ("tomato", "rice", "corn", "maize", "cotton", "chili", "chilli",
                "pepper")):
            continue
        if "___" in folder.name or any(m in low for m in
                                       ("healthy", "blight", "rust", "spot",
                                        "mold", "mites", "virus", "scab")):
            n = harvest_folder(folder, "Unknown")
            if n:
                print(f"  Unknown: +{n} from '{folder.name}'")


def try_kaggle() -> None:
    try:
        import kagglehub
    except ImportError:
        print("kagglehub not installed - skipping (pip install kagglehub, "
              "see TRAINING_GUIDE.md for the free token)")
        return
    for crop, slugs in KAGGLE_SLUGS.items():
        if count_images(OUT / crop) >= MIN_PER_CLASS:
            print(f"{crop}: already populated")
            continue
        for slug in slugs:
            try:
                print(f"Downloading {slug} ...")
                path = Path(kagglehub.dataset_download(slug))
                n = harvest_folder(path, crop)
                print(f"  {crop}: +{n} images")
            except Exception as e:  # noqa: BLE001 - try the next slug
                print(f"  failed: {e}")


def report() -> bool:
    print("\n--- dataset/crops status ---")
    ok = True
    for crop in ("Tomato", "Rice", "Cotton", "Chilli", "Maize", "Unknown"):
        n = count_images(OUT / crop)
        flag = "OK " if n >= MIN_PER_CLASS else "LOW"
        if n < MIN_PER_CLASS:
            ok = False
        print(f"  [{flag}] {crop}: {n} images (floor {MIN_PER_CLASS})")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, default=None,
                        help="local folder with crop/PlantVillage class folders")
    parser.add_argument("--skip-kaggle", action="store_true")
    args = parser.parse_args()

    if args.source:
        organize_from(args.source)
        harvest_unknown_from(args.source)
    if not args.skip_kaggle:
        try_kaggle()

    if report():
        print("\nDataset ready. Train with:")
        print("  python ai/training/train.py --dataset_dir ai/dataset/crops "
              "--epochs 12")
        print("Then copy the model to ai/models/crop_model.h5 and its class "
              "list to ai/models/crop_model_labels.txt.")
        return 0
    print("\nSome classes are below the floor - add sources or a local "
          "--source copy before training.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
