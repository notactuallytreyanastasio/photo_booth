#!/usr/bin/env python3
"""
Image enhancement for receipt printer output
Optimized for Raspberry Pi Zero with various artistic filters
"""

import sys
import os
from PIL import Image, ImageFilter, ImageOps, ImageEnhance
import numpy as np
from pathlib import Path

def floyd_steinberg_dither(image):
    """Apply Floyd-Steinberg dithering optimized for receipt printer"""
    img = image.convert('L')
    
    # Pre-process to handle over-exposure and improve contrast
    img_array = np.array(img, dtype=float)
    
    # 1. Check if image is over-exposed (too bright)
    mean_brightness = np.mean(img_array)
    
    if mean_brightness > 180:  # Over-exposed image
        # Apply stronger gamma to darken
        gamma = 1.5  # Greater than 1 darkens
        img_array = 255 * np.power(img_array / 255, gamma)
    elif mean_brightness < 80:  # Under-exposed image
        # Apply lighter gamma to brighten
        gamma = 0.7  # Less than 1 brightens
        img_array = 255 * np.power(img_array / 255, gamma)
    else:
        # Normal exposure - mild adjustment
        gamma = 1.1
        img_array = 255 * np.power(img_array / 255, gamma)
    
    # 2. Improve contrast using histogram stretching
    percentile_low = np.percentile(img_array, 5)
    percentile_high = np.percentile(img_array, 95)
    
    # More aggressive stretching for better definition
    if percentile_high - percentile_low > 20:
        img_array = np.clip((img_array - percentile_low) * 255 / (percentile_high - percentile_low), 0, 255)
    
    # 3. Apply mild sharpening for detail preservation
    img_temp = Image.fromarray(img_array.astype(np.uint8))
    img_temp = img_temp.filter(ImageFilter.UnsharpMask(radius=1, percent=100, threshold=2))
    img_array = np.array(img_temp, dtype=float)
    
    # 4. Apply Floyd-Steinberg dithering with adaptive threshold
    h, w = img_array.shape
    
    # Calculate adaptive threshold based on image brightness
    mean_brightness = np.mean(img_array)
    threshold = 110 if mean_brightness < 100 else 128  # Lower threshold for dark images
    
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

def sketch_effect(image):
    """Convert image to sketch-like appearance"""
    # Convert to grayscale
    gray = image.convert('L')
    
    # Create inverted image
    inverted = ImageOps.invert(gray)
    
    # Apply Gaussian blur to inverted image
    blurred = inverted.filter(ImageFilter.GaussianBlur(radius=10))
    
    # Blend the grayscale and blurred inverted using color dodge
    gray_array = np.array(gray, dtype=float)
    blurred_array = np.array(blurred, dtype=float)
    
    # Color dodge blend mode
    result = gray_array * 255 / (255 - blurred_array + 1e-10)
    result = np.clip(result, 0, 255)
    
    sketch = Image.fromarray(result.astype(np.uint8))
    
    # Enhance contrast
    enhancer = ImageEnhance.Contrast(sketch)
    sketch = enhancer.enhance(2.0)
    
    # Apply threshold for pure B&W
    return sketch.point(lambda x: 255 if x > 180 else 0)

def edge_detection(image):
    """Edge detection filter for line art effect"""
    gray = image.convert('L')
    
    # Find edges
    edges = gray.filter(ImageFilter.FIND_EDGES)
    
    # Invert to get black lines on white
    inverted = ImageOps.invert(edges)
    
    # Enhance contrast
    enhancer = ImageEnhance.Contrast(inverted)
    enhanced = enhancer.enhance(3.0)
    
    # Apply threshold
    return enhanced.point(lambda x: 255 if x > 200 else 0)

def halftone_effect(image, dot_size=4):
    """Create halftone effect optimized for thermal printing"""
    gray = image.convert('L')
    width, height = gray.size
    
    # Create new image for halftone
    halftone = Image.new('L', (width, height), 255)
    pixels = halftone.load()
    gray_pixels = gray.load()
    
    for y in range(0, height, dot_size):
        for x in range(0, width, dot_size):
            # Calculate average brightness in block
            total = 0
            count = 0
            for dy in range(min(dot_size, height - y)):
                for dx in range(min(dot_size, width - x)):
                    total += gray_pixels[x + dx, y + dy]
                    count += 1
            
            avg = total / count if count > 0 else 255
            
            # Draw dot based on brightness
            dot_radius = int((255 - avg) * dot_size / 255)
            for dy in range(min(dot_size, height - y)):
                for dx in range(min(dot_size, width - x)):
                    dist = ((dx - dot_size/2)**2 + (dy - dot_size/2)**2) ** 0.5
                    if dist <= dot_radius / 2:
                        pixels[x + dx, y + dy] = 0
    
    return halftone

def high_contrast_bw(image):
    """High contrast - inverted sketch effect for perfect detail preservation"""
    # Use the sketch effect but invert it
    gray = image.convert('L')
    
    # Create inverted image
    inverted = ImageOps.invert(gray)
    
    # Apply Gaussian blur to inverted image
    blurred = inverted.filter(ImageFilter.GaussianBlur(radius=10))
    
    # Blend the grayscale and blurred inverted using color dodge
    gray_array = np.array(gray, dtype=float)
    blurred_array = np.array(blurred, dtype=float)
    
    # Color dodge blend mode
    result = gray_array * 255 / (255 - blurred_array + 1e-10)
    result = np.clip(result, 0, 255)
    
    sketch = Image.fromarray(result.astype(np.uint8))
    
    # Enhance contrast
    enhancer = ImageEnhance.Contrast(sketch)
    sketch = enhancer.enhance(2.0)
    
    # Apply threshold for pure B&W (same as sketch)
    bw_sketch = sketch.point(lambda x: 255 if x > 180 else 0)
    
    # Now invert the result to get the contrast version
    return ImageOps.invert(bw_sketch)

def comic_effect(image):
    """Comic book/graphic novel effect with bold outlines and shading"""
    gray = image.convert('L')
    
    # Step 1: Create bold outlines using selective edge detection
    # Use Sobel-like filter for stronger edges
    edges = gray.filter(ImageFilter.FIND_EDGES)
    
    # Make edges thicker by dilating them
    edges = edges.filter(ImageFilter.MaxFilter(size=3))
    
    # Enhance edge contrast
    enhancer = ImageEnhance.Contrast(edges)
    bold_edges = enhancer.enhance(3.0)
    
    # Threshold edges to pure black/white
    edge_mask = bold_edges.point(lambda x: 0 if x < 100 else 255)
    
    # Step 2: Create posterized fill areas
    # Blur slightly to reduce noise
    smoothed = gray.filter(ImageFilter.GaussianBlur(radius=2))
    
    # Create 3-level posterization for shading
    posterized = ImageOps.posterize(smoothed, 2)
    
    # Convert to just 3 tones: white, gray pattern, black
    pixels = np.array(posterized)
    result = np.zeros_like(pixels)
    
    # Define thresholds for three zones
    dark_threshold = 85
    light_threshold = 170
    
    # Create patterns for mid-tone
    for y in range(pixels.shape[0]):
        for x in range(pixels.shape[1]):
            pixel = pixels[y, x]
            if pixel < dark_threshold:
                result[y, x] = 0  # Black
            elif pixel > light_threshold:
                result[y, x] = 255  # White
            else:
                # Checkerboard pattern for mid-tones
                if (x + y) % 2 == 0:
                    result[y, x] = 255
                else:
                    result[y, x] = 0
    
    posterized_result = Image.fromarray(result.astype(np.uint8))
    
    # Step 3: Combine edges with posterized areas
    # Edges override everything else
    edge_array = np.array(edge_mask)
    poster_array = np.array(posterized_result)
    
    # Where edges are black (0), use black; otherwise use posterized
    final = np.where(edge_array == 0, 0, poster_array)
    
    return Image.fromarray(final.astype(np.uint8))

def woodcut_effect(image):
    """Woodcut/linocut artistic effect"""
    gray = image.convert('L')
    
    # Apply strong posterization
    posterized = ImageOps.posterize(gray, 2)
    
    # Apply median filter to smooth
    smoothed = posterized.filter(ImageFilter.MedianFilter(size=5))
    
    # Find edges and combine
    edges = smoothed.filter(ImageFilter.FIND_EDGES)
    edges_inv = ImageOps.invert(edges)
    
    # Combine original and edges
    result = Image.blend(smoothed, edges_inv, 0.3)
    
    # Final threshold
    return result.point(lambda x: 255 if x > 100 else 0)

def lowlight_enhance(image):
    """Enhanced processing specifically for low-light conditions"""
    gray = image.convert('L')
    
    # Aggressive brightness boost for low-light
    # 1. Apply stronger gamma correction
    img_array = np.array(gray, dtype=float)
    
    # Very aggressive gamma for low light (0.4-0.5)
    gamma = 0.45
    img_array = 255 * np.power(img_array / 255, gamma)
    
    # 2. Adaptive histogram equalization-like enhancement
    # Boost dark regions more than bright regions
    percentile_low = np.percentile(img_array, 5)
    percentile_high = np.percentile(img_array, 95)
    
    # Stretch with bias toward brightening
    if percentile_high - percentile_low > 20:
        img_array = np.clip((img_array - percentile_low) * 300 / (percentile_high - percentile_low), 0, 255)
    
    # 3. Local contrast enhancement with stronger unsharp mask
    img_temp = Image.fromarray(img_array.astype(np.uint8))
    
    # Apply CLAHE-like local enhancement
    enhanced = ImageEnhance.Contrast(img_temp).enhance(1.8)
    enhanced_array = np.array(enhanced, dtype=float)
    
    # Strong unsharp mask for detail recovery
    blurred = enhanced.filter(ImageFilter.GaussianBlur(radius=3))
    blurred_array = np.array(blurred, dtype=float)
    
    # Stronger unsharp mask
    strength = 0.8
    enhanced_array = enhanced_array + (enhanced_array - blurred_array) * strength
    enhanced_array = np.clip(enhanced_array, 0, 255)
    
    # 4. Adaptive thresholding for final B&W conversion
    # Use lower threshold for dark images
    mean_brightness = np.mean(enhanced_array)
    threshold = 90 if mean_brightness < 80 else 110
    
    # Apply threshold with some dithering for smooth gradients
    h, w = enhanced_array.shape
    result = np.zeros_like(enhanced_array)
    
    for y in range(h):
        for x in range(w):
            # Add slight noise to prevent banding
            noise = np.random.normal(0, 5)
            pixel = enhanced_array[y, x] + noise
            result[y, x] = 255 if pixel > threshold else 0
    
    return Image.fromarray(result.astype(np.uint8))

def daylight_enhance(image):
    """Optimized processing for bright daylight conditions"""
    gray = image.convert('L')
    
    # For daylight, we need to preserve detail without over-brightening
    img_array = np.array(gray, dtype=float)
    
    # 1. Mild gamma correction to prevent washout
    gamma = 1.2  # Greater than 1 darkens the image slightly
    img_array = 255 * np.power(img_array / 255, gamma)
    
    # 2. Increase contrast to handle bright light washout
    # Find bright spots and reduce them
    percentile_low = np.percentile(img_array, 10)
    percentile_high = np.percentile(img_array, 90)
    
    # Compress dynamic range for bright images
    if percentile_high > 200:  # Very bright image
        # Apply S-curve to compress highlights
        img_array = np.where(img_array > 180, 
                            180 + (img_array - 180) * 0.5,  # Compress highlights
                            img_array)
    
    # 3. Enhance mid-tone contrast
    img_temp = Image.fromarray(img_array.astype(np.uint8))
    
    # Strong contrast enhancement for daylight
    enhanced = ImageEnhance.Contrast(img_temp).enhance(2.5)
    
    # Add slight sharpening for crisp details
    enhanced = enhanced.filter(ImageFilter.UnsharpMask(radius=2, percent=150, threshold=3))
    
    enhanced_array = np.array(enhanced, dtype=float)
    
    # 4. Adaptive threshold based on image statistics
    mean_brightness = np.mean(enhanced_array)
    std_brightness = np.std(enhanced_array)
    
    # Higher threshold for bright images to prevent too much black
    threshold = 140 if mean_brightness > 150 else 128
    
    # Apply threshold with edge preservation
    edges = enhanced.filter(ImageFilter.FIND_EDGES)
    edge_array = np.array(edges, dtype=float)
    
    # Combine threshold with edge information
    result = np.zeros_like(enhanced_array)
    for y in range(enhanced_array.shape[0]):
        for x in range(enhanced_array.shape[1]):
            # If it's an edge, make it black
            if edge_array[y, x] > 50:
                result[y, x] = 0
            else:
                # Otherwise use adaptive threshold
                result[y, x] = 255 if enhanced_array[y, x] > threshold else 0
    
    return Image.fromarray(result.astype(np.uint8))

def process_image(input_path, output_path, method='sketch', width=576):
    """Process image with specified method"""
    
    # Load image
    img = Image.open(input_path)
    
    # Calculate height maintaining aspect ratio
    aspect = img.height / img.width
    height = int(width * aspect)
    
    # Resize image
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    
    # Apply selected filter
    if method == 'sketch':
        processed = sketch_effect(img)
    elif method == 'edge':
        processed = edge_detection(img)
    elif method == 'dither':
        processed = floyd_steinberg_dither(img)
    elif method == 'halftone':
        processed = halftone_effect(img)
    elif method == 'contrast':
        processed = high_contrast_bw(img)
    elif method == 'comic':
        processed = comic_effect(img)
    elif method == 'woodcut':
        processed = woodcut_effect(img)
    elif method == 'lowlight':
        processed = lowlight_enhance(img)
    elif method == 'daylight':
        processed = daylight_enhance(img)
    else:
        print(f"Unknown method: {method}")
        return False
    
    # Convert to 1-bit for smallest file size
    processed = processed.convert('1')
    
    # Save processed image
    processed.save(output_path, 'PNG', optimize=True)
    print(f"Saved {method} effect to {output_path}")
    
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage: python enhance_receipt_image.py <input_image> [method]")
        print("\nAvailable methods:")
        print("  sketch   - Pencil sketch effect (default)")
        print("  edge     - Edge detection for line art")
        print("  dither   - Floyd-Steinberg dithering")
        print("  halftone - Halftone newspaper effect")
        print("  contrast - High contrast B&W (inverted sketch)")
        print("  comic    - Comic book/graphic novel style")
        print("  woodcut  - Woodcut/linocut effect")
        print("  lowlight - Optimized for low-light conditions")
        print("  daylight - Optimized for bright daylight")
        print("  all      - Generate all effects")
        print("\nExample:")
        print("  python enhance_receipt_image.py me.jpg sketch")
        print("  python enhance_receipt_image.py me.jpg all")
        sys.exit(1)
    
    input_file = sys.argv[1]
    method = sys.argv[2] if len(sys.argv) > 2 else 'sketch'
    
    if not os.path.exists(input_file):
        print(f"Error: File '{input_file}' not found")
        sys.exit(1)
    
    # Handle 'all' method
    if method == 'all':
        methods = ['sketch', 'edge', 'dither', 'halftone', 'contrast', 'comic', 'woodcut', 'lowlight', 'daylight']
        print(f"Processing {input_file} with all methods...")
        for m in methods:
            base = Path(input_file).stem
            ext = Path(input_file).suffix
            output_file = f"{base}_{m}_receipt{ext}"
            success = process_image(input_file, output_file, m)
            if not success:
                print(f"✗ Failed to process {m} effect")
        print("✓ All effects processed!")
    else:
        # Generate output filename
        base = Path(input_file).stem
        ext = Path(input_file).suffix
        output_file = f"{base}_{method}_receipt{ext}"
        
        # Process image
        success = process_image(input_file, output_file, method)
        
        if success:
            print(f"✓ Enhanced image saved as {output_file}")
            print(f"  Ready for receipt printer!")
        else:
            print("✗ Failed to process image")
            sys.exit(1)

if __name__ == "__main__":
    main()