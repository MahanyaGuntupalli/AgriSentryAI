"""
Disease Model Training Pipeline
Fine-tunes MobileNetV2 on tomato disease dataset.

Usage:
    python train.py --dataset_dir ../dataset/tomato --epochs 20 --batch_size 32
"""
import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import tensorflow as tf
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.layers import Dense, GlobalAveragePooling2D, Dropout
from tensorflow.keras.models import Model
from tensorflow.keras.callbacks import ModelCheckpoint, EarlyStopping, ReduceLROnPlateau

from preprocessing.preprocess import get_train_datagen, get_val_datagen, IMG_SIZE, BATCH_SIZE
from models.model_loader import get_model_path, save_labels

def build_model(num_classes):
    """Build MobileNetV2-based classifier."""
    base = MobileNetV2(
        weights="imagenet",
        include_top=False,
        input_shape=(224, 224, 3)
    )
    base.trainable = False  # Freeze base initially

    x = base.output
    x = GlobalAveragePooling2D()(x)
    x = Dropout(0.3)(x)
    x = Dense(128, activation="relu")(x)
    x = Dropout(0.2)(x)
    predictions = Dense(num_classes, activation="softmax")(x)

    model = Model(inputs=base.input, outputs=predictions)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss="categorical_crossentropy",
        metrics=["accuracy", tf.keras.metrics.Precision(), tf.keras.metrics.Recall()]
    )
    return model, base

def train(dataset_dir, epochs=20, batch_size=32, fine_tune_epochs=10):
    """
    Train the disease classification model.

    Args:
        dataset_dir: Directory with class subfolders
        epochs: Training epochs (frozen base)
        batch_size: Batch size
        fine_tune_epochs: Additional epochs with unfrozen base
    """
    if not os.path.exists(dataset_dir):
        print(f"ERROR: Dataset directory not found: {dataset_dir}")
        print("Expected structure:")
        print("  dataset/tomato/")
        print("    Healthy/")
        print("    Early Blight/")
        print("    Late Blight/")
        print("    Bacterial Spot/")
        sys.exit(1)

    train_gen = get_train_datagen()
    val_gen = get_val_datagen()

    train_data = train_gen.flow_from_directory(
        dataset_dir,
        target_size=IMG_SIZE,
        batch_size=batch_size,
        class_mode="categorical",
        subset="training",
        shuffle=True
    )

    val_data = val_gen.flow_from_directory(
        dataset_dir,
        target_size=IMG_SIZE,
        batch_size=batch_size,
        class_mode="categorical",
        subset="validation",
        shuffle=False
    )

    class_indices = train_data.class_indices
    labels = [k for k, v in sorted(class_indices.items(), key=lambda x: x[1])]
    num_classes = len(labels)

    print(f"\nFound {train_data.samples} training images")
    print(f"Found {val_data.samples} validation images")
    print(f"Classes: {labels}\n")

    # Save labels
    save_labels(labels)

    # Build model
    model, base = build_model(num_classes)
    model.summary()

    # Callbacks
    checkpoint = ModelCheckpoint(
        get_model_path(),
        monitor="val_accuracy",
        save_best_only=True,
        mode="max",
        verbose=1
    )
    early_stop = EarlyStopping(monitor="val_loss", patience=5, restore_best_weights=True)
    reduce_lr = ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=3, min_lr=1e-6)

    # Phase 1: Train with frozen base
    print("\n--- Phase 1: Training with frozen base ---")
    history1 = model.fit(
        train_data,
        validation_data=val_data,
        epochs=epochs,
        callbacks=[checkpoint, early_stop, reduce_lr]
    )

    # Phase 2: Fine-tune with unfrozen base
    if fine_tune_epochs > 0:
        print("\n--- Phase 2: Fine-tuning ---")
        base.trainable = True
        for layer in base.layers[:-30]:
            layer.trainable = False

        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
            loss="categorical_crossentropy",
            metrics=["accuracy", tf.keras.metrics.Precision(), tf.keras.metrics.Recall()]
        )

        history2 = model.fit(
            train_data,
            validation_data=val_data,
            epochs=fine_tune_epochs,
            callbacks=[checkpoint, early_stop, reduce_lr]
        )

    # Final save
    model.save(get_model_path())
    print(f"\nModel saved to: {get_model_path()}")
    print(f"Labels saved. Class mapping: {class_indices}")

    # Evaluate
    print("\n--- Final Evaluation ---")
    loss, acc, prec, rec = model.evaluate(val_data)
    print(f"Validation Accuracy: {acc:.4f}")
    print(f"Validation Precision: {prec:.4f}")
    print(f"Validation Recall: {rec:.4f}")

    return model, history1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train AgriSentry AI Disease Model")
    parser.add_argument("--dataset_dir", default="../dataset/tomato", help="Path to dataset")
    parser.add_argument("--epochs", type=int, default=20, help="Training epochs")
    parser.add_argument("--batch_size", type=int, default=32, help="Batch size")
    parser.add_argument("--fine_tune_epochs", type=int, default=10, help="Fine-tune epochs")
    args = parser.parse_args()

    train(args.dataset_dir, args.epochs, args.batch_size, args.fine_tune_epochs)
