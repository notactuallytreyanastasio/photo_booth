#!/usr/bin/env python3
"""
Standalone script to print images directly to the receipt printer
Usage: python imgprint.py <image_file1> [image_file2] [image_file3] ...
Prints all images in sequence, cutting only after the last one
"""

import sys
import os
from pathlib import Path

# Add parent directory to path to import local modules
sys.path.insert(0, str(Path(__file__).parent.parent))

from printer.custom_printer import FullWidthPrinter

def print_images(image_paths):
    """Print multiple images in sequence, cutting only after the last one"""
    
    # Check all files exist first
    for image_path in image_paths:
        if not os.path.exists(image_path):
            print(f"Error: File '{image_path}' not found")
            return False
    
    try:
        # Initialize printer once
        printer = FullWidthPrinter()
        
        total = len(image_paths)
        
        for i, image_path in enumerate(image_paths, 1):
            print(f"[{i}/{total}] Printing {image_path}...")
            
            # Only add cuts after the last image
            add_cuts = (i == total)
            
            # Print the image
            success = printer.print_image(
                image_path,
                width=576,  # Full width for 80mm paper
                dither_method='floyd_steinberg',
                add_cuts=add_cuts
            )
            
            if not success:
                print(f"✗ Failed to print {image_path}")
                return False
        
        print(f"✓ All {total} images printed successfully!")
        return True
            
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python imgprint.py <image_file1> [image_file2] ...")
        print("\nExamples:")
        print("  python imgprint.py photo.jpg")
        print("  python imgprint.py photo1.jpg photo2.jpg photo3.jpg")
        print("  python imgprint.py me_*.jpg")
        sys.exit(1)
    
    image_files = sys.argv[1:]
    print(f"Preparing to print {len(image_files)} image(s)...")
    
    success = print_images(image_files)
    sys.exit(0 if success else 1)