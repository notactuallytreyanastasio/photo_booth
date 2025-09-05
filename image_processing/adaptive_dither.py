#!/usr/bin/env python3
"""
Adaptive Floyd-Steinberg dithering for different lighting conditions
"""

import sys
from PIL import Image, ImageEnhance, ImageFilter
import numpy as np
from pathlib import Path

def dither_for_lowlight(image):
    """Optimize dithering for low-light/dark photos"""
    img = image.convert('L')
    img_array = np.array(img, dtype=float)
    
    # Aggressive brightening for low light
    gamma = 0.5  # Strong brightening
    img_array = 255 * np.power(img_array / 255, gamma)
    
    # Stretch histogram aggressively
    percentile_low = np.percentile(img_array, 2)
    percentile_high = np.percentile(img_array, 98)
    if percentile_high - percentile_low > 10:
        img_array = np.clip((img_array - percentile_low) * 300 / (percentile_high - percentile_low), 0, 255)
    
    # Lower threshold for dark images
    threshold = 90
    
    # Floyd-Steinberg dithering
    h, w = img_array.shape
    for y in range(h):
        for x in range(w):
            old_pixel = img_array[y, x]
            new_pixel = 255 if old_pixel > threshold else 0
            img_array[y, x] = new_pixel
            error = old_pixel - new_pixel
            
            if x + 1 < w:
                img_array[y, x + 1] += error * 7 / 16
            if y + 1 < h:
                if x > 0:
                    img_array[y + 1, x - 1] += error * 3 / 16
                img_array[y + 1, x] += error * 5 / 16
                if x + 1 < w:
                    img_array[y + 1, x + 1] += error * 1 / 16
    
    return Image.fromarray(np.clip(img_array, 0, 255).astype(np.uint8))

def dither_for_auto(image):
    """Standard dithering for normal lighting"""
    img = image.convert('L')
    img_array = np.array(img, dtype=float)
    
    # Mild gamma adjustment
    gamma = 0.9
    img_array = 255 * np.power(img_array / 255, gamma)
    
    # Standard histogram stretch
    percentile_low = np.percentile(img_array, 5)
    percentile_high = np.percentile(img_array, 95)
    if percentile_high - percentile_low > 20:
        img_array = np.clip((img_array - percentile_low) * 255 / (percentile_high - percentile_low), 0, 255)
    
    # Standard threshold
    threshold = 128
    
    # Floyd-Steinberg dithering
    h, w = img_array.shape
    for y in range(h):
        for x in range(w):
            old_pixel = img_array[y, x]
            new_pixel = 255 if old_pixel > threshold else 0
            img_array[y, x] = new_pixel
            error = old_pixel - new_pixel
            
            if x + 1 < w:
                img_array[y, x + 1] += error * 7 / 16
            if y + 1 < h:
                if x > 0:
                    img_array[y + 1, x - 1] += error * 3 / 16
                img_array[y + 1, x] += error * 5 / 16
                if x + 1 < w:
                    img_array[y + 1, x + 1] += error * 1 / 16
    
    return Image.fromarray(np.clip(img_array, 0, 255).astype(np.uint8))

def dither_for_bright(image):
    """Optimize dithering for bright/overexposed photos"""
    img = image.convert('L')
    img_array = np.array(img, dtype=float)
    
    # Mild darkening to recover highlights
    gamma = 1.3  # Reduced from 1.8 - much milder darkening
    img_array = 255 * np.power(img_array / 255, gamma)
    
    # Compress highlights gently
    img_array = np.where(img_array > 220, 
                        220 + (img_array - 220) * 0.5,  # Gentler compression
                        img_array)
    
    # Slightly higher threshold for bright images
    threshold = 135  # Reduced from 145
    
    # Floyd-Steinberg dithering
    h, w = img_array.shape
    for y in range(h):
        for x in range(w):
            old_pixel = img_array[y, x]
            new_pixel = 255 if old_pixel > threshold else 0
            img_array[y, x] = new_pixel
            error = old_pixel - new_pixel
            
            if x + 1 < w:
                img_array[y, x + 1] += error * 7 / 16
            if y + 1 < h:
                if x > 0:
                    img_array[y + 1, x - 1] += error * 3 / 16
                img_array[y + 1, x] += error * 5 / 16
                if x + 1 < w:
                    img_array[y + 1, x + 1] += error * 1 / 16
    
    return Image.fromarray(np.clip(img_array, 0, 255).astype(np.uint8))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python adaptive_dither.py <input.jpg> <mode>")
        print("Modes: lowlight, auto, bright")
        sys.exit(1)
    
    input_file = sys.argv[1]
    mode = sys.argv[2]
    
    img = Image.open(input_file)
    
    # Resize to receipt width
    aspect = img.height / img.width
    img = img.resize((576, int(576 * aspect)), Image.Resampling.LANCZOS)
    
    if mode == "lowlight":
        result = dither_for_lowlight(img)
    elif mode == "auto":
        result = dither_for_auto(img)
    elif mode == "bright":
        result = dither_for_bright(img)
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
    
    # Save with appropriate name
    base = Path(input_file).stem
    output = f"{base}_{mode}_receipt.jpg"
    result.convert('1').save(output, 'JPEG')
    print(f"Saved to {output}")