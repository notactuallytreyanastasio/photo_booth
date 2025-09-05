#!/bin/bash

# Simple photo booth with text signatures printed separately
# Configured for Raspberry Pi with receipt printer

# Configuration
# Get the script's parent directory (photo_booth root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOTO_BOOTH_ROOT="$(dirname "$SCRIPT_DIR")"

# Set paths relative to photo_booth installation
PHOTO_DIR="${PHOTO_DIR:-~/pics}"
PRINTER_LIB="${PRINTER_LIB:-$PHOTO_BOOTH_ROOT}"
VIRTUAL_ENV="${VIRTUAL_ENV:-~/myenv}"

# Create photo directory if it doesn't exist
mkdir -p "$(eval echo $PHOTO_DIR)"

# Activate virtual environment if exists
if [ -f "$VIRTUAL_ENV/bin/activate" ]; then
    source "$VIRTUAL_ENV/bin/activate"
fi

# Function to print text as image
print_text() {
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
text = '''$1'''
img = Image.new('L', (576, 60), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 14)
except:
    font = ImageFont.load_default()
draw.text((10, 10), text, font=font, fill=0)
img.save('/tmp/text.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/text.png >/dev/null 2>&1
}

# Function to print countdown
print_countdown() {
    local number=$1
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('L', (576, 100), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 72)
except:
    font = ImageFont.load_default()
draw.text((250, 10), '$number', font=font, fill=0)
img.save('/tmp/count.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/count.png >/dev/null 2>&1
}

# Function to create SHA signature image
create_sha_image() {
    local sha=$1
    local output=$2
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('L', (576, 25), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 9)
except:
    font = ImageFont.load_default()
draw.text((10, 5), 'SHA: $sha', font=font, fill=0)
img.save('$output')
"
}

# Function to create signature footer
create_signature() {
    local date=$1
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('L', (576, 30), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 9)
except:
    font = ImageFont.load_default()
draw.text((10, 5), 'by @bobbby.online | $date', font=font, fill=0)
img.save('/tmp/sig.png')
"
}

# Main loop
print_text "READY - PRESS ENTER TO TAKE PHOTO"

while true; do
    # Wait for ENTER
    read
    
    # Countdown
    for i in 3 2 1; do
        print_countdown $i
        sleep 0.5
    done
    
    cd "$(eval echo $PHOTO_DIR)"
    
    # Take all 3 photos with different settings
    rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo1.jpg --awb auto
    rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo2.jpg --awb auto --contrast 1.5 --sharpness 1.5
    rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo3.jpg --awb auto --ev -0.5 --contrast 1.2
    
    # Calculate SHAs
    SHA1=$(sha256sum photo1.jpg | cut -c1-24)
    SHA2=$(sha256sum photo2.jpg | cut -c1-24)
    SHA3=$(sha256sum photo3.jpg | cut -c1-24)
    
    # Process photos for 3 different lighting scenarios
    # Strip 1: Low light optimization
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg lowlight
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg lowlight
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg lowlight
    
    # Strip 2: Auto/normal lighting
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg auto
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg auto
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg auto
    
    # Strip 3: Bright light optimization
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg bright
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg bright
    python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg bright
    
    DATE=$(date '+%Y-%m-%d %H:%M')
    
    # Create SHA images
    create_sha_image "$SHA1" "/tmp/sha1.png"
    create_sha_image "$SHA2" "/tmp/sha2.png"
    create_sha_image "$SHA3" "/tmp/sha3.png"
    
    # Create signature
    create_signature "$DATE"
    
    # Print Strip 1: Low light versions with SHAs
    python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_lowlight_receipt.jpg /tmp/sha1.png \
        photo2_lowlight_receipt.jpg /tmp/sha2.png \
        photo3_lowlight_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png >/dev/null 2>&1
    
    # Print Strip 2: Auto/normal versions with SHAs
    python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_auto_receipt.jpg /tmp/sha1.png \
        photo2_auto_receipt.jpg /tmp/sha2.png \
        photo3_auto_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png >/dev/null 2>&1
    
    # Print Strip 3: Bright light versions with SHAs
    python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_bright_receipt.jpg /tmp/sha1.png \
        photo2_bright_receipt.jpg /tmp/sha2.png \
        photo3_bright_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png >/dev/null 2>&1
done