# Photo Booth Receipt Printer Library

Standalone library for the photo booth receipt printer system, extracted from the Hermes project.

## Directory Structure

```
photo_booth_lib/
├── printer/                 # Printer interfaces
│   ├── receipt_printer.py   # Base printer class with ESC/POS commands
│   └── custom_printer.py    # Full-width printer implementation
├── image_processing/        # Image processing modules
│   ├── enhance_receipt_image.py  # Various artistic filters
│   └── adaptive_dither.py        # Lighting-adaptive dithering
├── scripts/                 # Main scripts
│   ├── photo_booth.sh       # Main photo booth loop
│   └── imgprint.py          # Direct image printing utility
└── requirements.txt         # Python dependencies
```

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Configure printer name in CUPS (default: EPSON_TM_m50)

## Usage

### Run Photo Booth
```bash
bash scripts/photo_booth.sh
```

### Print Images Directly
```bash
python scripts/imgprint.py image1.jpg image2.jpg
```

### Apply Image Filters
```bash
# All available filters
python image_processing/enhance_receipt_image.py photo.jpg all

# Specific filter
python image_processing/enhance_receipt_image.py photo.jpg sketch
```

### Adaptive Dithering
```bash
# For different lighting conditions
python image_processing/adaptive_dither.py photo.jpg lowlight
python image_processing/adaptive_dither.py photo.jpg auto
python image_processing/adaptive_dither.py photo.jpg bright
```

## Configuration

Environment variables:
- `PHOTO_DIR`: Directory for saving photos (default: ~/receipts)
- `PRINTER_LIB`: Path to this library (default: ~/receipts/photo_booth_lib)
- `VIRTUAL_ENV`: Python virtual environment path (optional)

## Features

- Full-width 576px printing (80mm thermal paper)
- Multiple artistic filters (sketch, edge, halftone, comic, etc.)
- Adaptive dithering for different lighting conditions
- Multi-image printing with single cut
- SHA256 checksums for photo verification
- Polaroid-style white borders