"""
Dataset Preparation Helper
Downloads or organizes tomato disease dataset.

Expected structure after preparation:
    dataset/tomato/
        Healthy/
        Early Blight/
        Late Blight/
        Bacterial Spot/

For MVP development, you can use the PlantVillage dataset:
    https://github.com/spMohanty/PlantVillage-Dataset
"""
import os
import shutil
from pathlib import Path

TOMATO_CLASSES = ["Healthy", "Early Blight", "Late Blight", "Bacterial Spot"]

def create_dataset_structure(base_dir="../dataset/tomato"):
    """Create empty folder structure for dataset."""
    base = Path(base_dir)
    for cls in TOMATO_CLASSES:
        (base / cls).mkdir(parents=True, exist_ok=True)
    print(f"Dataset structure created at {base_dir}")
    for cls in TOMATO_CLASSES:
        count = len(list((base / cls).glob("*")))
        print(f"  {cls}: {count} images")

def validate_dataset(base_dir="../dataset/tomato"):
    """Check dataset structure and report statistics."""
    base = Path(base_dir)
    if not base.exists():
        print(f"ERROR: Dataset directory not found: {base_dir}")
        return False

    total = 0
    for cls in TOMATO_CLASSES:
        cls_dir = base / cls
        if not cls_dir.exists():
            print(f"WARNING: Missing class folder: {cls}")
            continue
        count = len(list(cls_dir.glob("*")))
        total += count
        print(f"  {cls}: {count} images")

    print(f"\nTotal images: {total}")
    if total < 100:
        print("WARNING: Very small dataset. Consider collecting more images.")
    return total > 0

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--create", action="store_true", help="Create folder structure")
    parser.add_argument("--validate", action="store_true", help="Validate existing dataset")
    parser.add_argument("--dir", default="../dataset/tomato", help="Dataset directory")
    args = parser.parse_args()

    if args.create:
        create_dataset_structure(args.dir)
    if args.validate:
        validate_dataset(args.dir)
