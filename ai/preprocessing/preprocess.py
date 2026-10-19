"""
Image Preprocessing Pipeline
Resizes, normalizes, and augments images for model input.
"""
import numpy as np
from tensorflow.keras.preprocessing.image import ImageDataGenerator

IMG_SIZE = (224, 224)
BATCH_SIZE = 32

def get_train_datagen():
    """Data augmentation for training."""
    return ImageDataGenerator(
        rescale=1.0/255.0,
        rotation_range=30,
        width_shift_range=0.2,
        height_shift_range=0.2,
        shear_range=0.2,
        zoom_range=0.2,
        horizontal_flip=True,
        vertical_flip=True,
        brightness_range=[0.8, 1.2],
        fill_mode="nearest",
        validation_split=0.2
    )

def get_val_datagen():
    """No augmentation for validation."""
    return ImageDataGenerator(
        rescale=1.0/255.0,
        validation_split=0.2
    )

def preprocess_single_image(image_path):
    """Preprocess a single image for inference."""
    from tensorflow.keras.preprocessing import image as keras_image
    img = keras_image.load_img(image_path, target_size=IMG_SIZE)
    img_array = keras_image.img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0) / 255.0
    return img_array
