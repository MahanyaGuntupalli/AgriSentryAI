"""
Download the PlantVillage TOMATO subset and arrange it for AgriSentry training.

Creates (next to this file's ai/ folder):
    dataset/tomato/
        Healthy/            (Tomato___healthy)
        Early Blight/       (Tomato___Early_blight)
        Late Blight/        (Tomato___Late_blight)
        Bacterial Spot/     (Tomato___Bacterial_spot)

Three ways to get the data, tried in order:
  1. --source <dir>          you already downloaded a PlantVillage copy yourself
  2. Kaggle via kagglehub    automatic; needs `pip install kagglehub` and a
                             free Kaggle account token (see TRAINING_GUIDE.md)
  3. No-auth Git fallback    clones a public GitHub mirror of the dataset
                             (~250 MB for the four classes) - no account at all

Usage:
    python download_plantvillage.py                  # auto: kaggle, then git
    python download_plantvillage.py --source D:/pv   # use your own copy
    python download_plantvillage.py --git            # force the git fallback
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

AI_DIR = Path(__file__).resolve().parents[1]
DATASET_DIR = AI_DIR / "dataset" / "tomato"

# PlantVillage folder name -> AgriSentry class name
CLASS_MAP = {
    "Tomato___healthy": "Healthy",
    "Tomato___Early_blight": "Early Blight",
    "Tomato___Late_blight": "Late Blight",
    "Tomato___Bacterial_spot": "Bacterial Spot",
}

# Public mirrors carrying the tomato folders directly (no Kaggle account).
GIT_MIRRORS = [
    "https://github.com/spMohanty/PlantVillage-Dataset.git",
    "https://github.com/ECBTyagi/PlantVillage-Dataset.git",
]


def count_images(folder: Path) -> int:
    return sum(1 for p in folder.rglob("*") if p.suffix.lower() in {".jpg", ".jpeg", ".png"})


def link_or_copy(src: Path, dst: Path) -> None:
    """Hardlink when possible (instant, no extra disk), else copy."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        return
    try:
        dst.hardlink_to(src)
    except OSError:
        shutil.copy2(src, dst)


def organize_from(source_root: Path) -> bool:
    """Find CLASS_MAP folders anywhere under source_root and build dataset/."""
    print(f"Looking for tomato classes under: {source_root}")
    found = {}
    for folder in source_root.rglob("*"):
        if folder.is_dir() and folder.name in CLASS_MAP and folder.name not in found:
            found[folder.name] = folder
    if not found:
        print("  no tomato class folders found there")
        return False

    DATASET_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    for pv_name, class_name in CLASS_MAP.items():
        src = found.get(pv_name)
        dst = DATASET_DIR / class_name
        if src is None:
            print(f"  MISSING: {pv_name}  ->  dataset/tomato/{class_name} stays empty")
            continue
        n = 0
        for img in src.iterdir():
            if img.suffix.lower() in {".jpg", ".jpeg", ".png"}:
                link_or_copy(img, dst / img.name)
                n += 1
        total += n
        print(f"  {class_name}: {n} images")
    print(f"Total: {total} images in {DATASET_DIR}")
    return all((DATASET_DIR / c).exists() and count_images(DATASET_DIR / c) > 0
               for c in CLASS_MAP.values())


def try_kaggle() -> bool:
    """Download via kagglehub (needs pip install kagglehub + Kaggle token)."""
    try:
        import kagglehub  # noqa: F401
    except ImportError:
        print("kagglehub not installed - skipping Kaggle source "
              "(pip install kagglehub)")
        return False
    for slug in ("abdallahalidev/plantvillage-dataset",
                 "emmarex/plantdisease"):
        try:
            print(f"Downloading {slug} via kagglehub ...")
            path = Path(kagglehub.dataset_download(slug))
            return organize_from(path)
        except Exception as e:  # noqa: BLE001 - report and try the next source
            print(f"  Kaggle download failed: {e}")
    return False


def try_git() -> bool:
    """Clone a public PlantVillage mirror - no account required."""
    git = shutil.which("git")
    if not git:
        print("git not found on PATH - cannot use the Git fallback")
        return False
    for url in GIT_MIRRORS:
        tmp = AI_DIR / "dataset" / "_pv_clone"
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)
        print(f"Cloning {url} (this can take several minutes) ...")
        try:
            subprocess.run([git, "clone", "--depth", "1", url, str(tmp)],
                           check=True)
        except subprocess.CalledProcessError:
            continue
        # Mirror layouts vary; also accept the color version, which uses the
        # same folder names under raw/color/.
        if organize_from(tmp):
            return True
    if tmp.exists():
        shutil.rmtree(tmp, ignore_errors=True)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, default=None,
                        help="local folder that already contains the "
                             "PlantVillage tomato folders")
    parser.add_argument("--git", action="store_true",
                        help="skip Kaggle and use the Git fallback")
    args = parser.parse_args()

    if count_images(DATASET_DIR) > 1000:
        print(f"dataset/tomato already populated ({count_images(DATASET_DIR)} "
              f"images) - nothing to do")
        return 0

    if args.source:
        ok = organize_from(args.source)
    elif args.git:
        ok = try_git()
    else:
        ok = try_kaggle() or try_git()

    if not ok:
        print(
            "\nAutomatic download failed. Manual options:\n"
            "  1. Kaggle (free account): kaggle.com/datasets/"
            "abdallahalidev/plantvillage-dataset\n"
            "  2. Any GitHub mirror - search: Tomato___Early_blight\n"
            f"Then rerun with:  python {Path(sys.argv[0]).name} --source <folder>"
        )
        return 1
    print("\nDataset ready. Next step:")
    print("  python ai/training/train.py --dataset_dir ai/dataset/tomato "
          "--epochs 12")
    return 0


if __name__ == "__main__":
    sys.exit(main())
