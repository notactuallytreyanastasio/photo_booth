#!/bin/bash

# Test script to verify all paths are correct

# Get the script's parent directory (photo_booth root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOTO_BOOTH_ROOT="$SCRIPT_DIR"

# Set paths relative to photo_booth installation
PHOTO_DIR="${PHOTO_DIR:-~/pics}"
PRINTER_LIB="${PRINTER_LIB:-$PHOTO_BOOTH_ROOT}"
VIRTUAL_ENV="${VIRTUAL_ENV:-~/myenv}"

echo "=== Path Configuration ==="
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "PHOTO_BOOTH_ROOT: $PHOTO_BOOTH_ROOT"
echo "PHOTO_DIR: $PHOTO_DIR"
echo "PHOTO_DIR expanded: $(eval echo $PHOTO_DIR)"
echo "PRINTER_LIB: $PRINTER_LIB"
echo "VIRTUAL_ENV: $VIRTUAL_ENV"
echo ""

echo "=== Checking Files ==="
echo -n "imgprint.py: "
if [ -f "$PRINTER_LIB/scripts/imgprint.py" ]; then
    echo "✓ Found at $PRINTER_LIB/scripts/imgprint.py"
else
    echo "✗ NOT FOUND at $PRINTER_LIB/scripts/imgprint.py"
fi

echo -n "adaptive_dither.py: "
if [ -f "$PRINTER_LIB/image_processing/adaptive_dither.py" ]; then
    echo "✓ Found at $PRINTER_LIB/image_processing/adaptive_dither.py"
else
    echo "✗ NOT FOUND at $PRINTER_LIB/image_processing/adaptive_dither.py"
fi

echo -n "custom_printer.py: "
if [ -f "$PRINTER_LIB/printer/custom_printer.py" ]; then
    echo "✓ Found at $PRINTER_LIB/printer/custom_printer.py"
else
    echo "✗ NOT FOUND at $PRINTER_LIB/printer/custom_printer.py"
fi

echo ""
echo "=== Python Import Test ==="
python3 -c "
import sys
sys.path.insert(0, '$PRINTER_LIB')
try:
    from printer.custom_printer import FullWidthPrinter
    print('✓ Successfully imported FullWidthPrinter')
except ImportError as e:
    print(f'✗ Failed to import: {e}')
"

echo ""
echo "=== Creating photo directory if needed ==="
mkdir -p "$(eval echo $PHOTO_DIR)"
if [ -d "$(eval echo $PHOTO_DIR)" ]; then
    echo "✓ Photo directory exists: $(eval echo $PHOTO_DIR)"
else
    echo "✗ Failed to create photo directory"
fi