"""
Disease Inference Pipeline
Loads model and runs prediction on a single image.
"""
import os
import sys
import numpy as np

# Add parent to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from models.model_loader import get_model_path, load_labels

def predict_disease(image_path, model_path=None):
    """
    Run disease prediction on an image.

    Args:
        image_path: Path to leaf image
        model_path: Optional custom model path

    Returns:
        dict with disease, confidence, all_probabilities
    """
    import tensorflow as tf
    from preprocessing.preprocess import preprocess_single_image

    if model_path is None:
        model_path = get_model_path()

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model not found at {model_path}. Train the model first.")

    model = tf.keras.models.load_model(model_path)
    labels = load_labels()

    img_array = preprocess_single_image(image_path)
    predictions = model.predict(img_array, verbose=0)
    predicted_idx = int(np.argmax(predictions[0]))
    confidence = float(predictions[0][predicted_idx])

    return {
        "disease": labels[predicted_idx],
        "confidence": round(confidence, 4),
        "all_probabilities": {
            label: round(float(prob), 4)
            for label, prob in zip(labels, predictions[0])
        }
    }

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="Path to leaf image")
    parser.add_argument("--model", default=None, help="Path to model file")
    args = parser.parse_args()

    result = predict_disease(args.image, args.model)
    print(f"\nPrediction: {result['disease']}")
    print(f"Confidence: {result['confidence']:.2%}")
    print("\nAll probabilities:")
    for label, prob in result["all_probabilities"].items():
        print(f"  {label}: {prob:.2%}")
