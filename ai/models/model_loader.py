"""
Model Loader for AgriSentry AI Disease Detection
Loads trained MobileNetV2 model and class labels.
"""
import os
import json

def get_model_path():
    """Return absolute path to saved model."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "tomato_disease_model.h5"))

def get_labels_path():
    """Return absolute path to labels file."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "labels.txt"))

def load_labels():
    """Load class labels from text file."""
    path = get_labels_path()
    if os.path.exists(path):
        with open(path, "r") as f:
            return [line.strip() for line in f if line.strip()]
    return ["Healthy", "Early Blight", "Late Blight", "Bacterial Spot"]

def save_labels(labels):
    """Save class labels to text file."""
    path = get_labels_path()
    with open(path, "w") as f:
        for label in labels:
            f.write(label + "\n")
