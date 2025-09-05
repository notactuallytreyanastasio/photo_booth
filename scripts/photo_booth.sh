#!/bin/bash

# Simple photo booth with text signatures printed separately
# Configured for Raspberry Pi with receipt printer

# Check for verbose mode
VERBOSE_MODE=0
if [ "$1" = "v" ]; then
    VERBOSE_MODE=1
    echo "VERBOSE MODE ENABLED - Debug logs will be printed after each session"
fi

# Configuration
# Get the script's parent directory (photo_booth root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHOTO_BOOTH_ROOT="$(dirname "$SCRIPT_DIR")"

# Set paths relative to photo_booth installation
PHOTO_DIR="${PHOTO_DIR:-~/pics}"
PRINTER_LIB="${PRINTER_LIB:-$PHOTO_BOOTH_ROOT}"
VIRTUAL_ENV="${VIRTUAL_ENV:-~/myenv}"
DEBUG_LOG="/tmp/photo_booth_debug.log"
ERROR_LOG="/tmp/photo_booth_error.log"
SESSION_LOG="/tmp/photo_booth_session.log"

# Create photo directory if it doesn't exist
mkdir -p "$(eval echo $PHOTO_DIR)"

# Initialize debug logging
exec 2> >(tee -a "$ERROR_LOG")
exec 1> >(tee -a "$DEBUG_LOG")

echo "=== Photo Booth Started: $(date) ===" >> "$DEBUG_LOG"
echo "PHOTO_DIR: $PHOTO_DIR" >> "$DEBUG_LOG"
echo "PRINTER_LIB: $PRINTER_LIB" >> "$DEBUG_LOG"
echo "VIRTUAL_ENV: $VIRTUAL_ENV" >> "$DEBUG_LOG"

# Activate virtual environment if exists
if [ -f "$VIRTUAL_ENV/bin/activate" ]; then
    source "$VIRTUAL_ENV/bin/activate"
    echo "Virtual environment activated" >> "$DEBUG_LOG"
fi

# Function to print session debug (for verbose mode)
print_session_debug() {
    local session_title="SESSION DEBUG $(date '+%H:%M:%S')"
    
    # Create session debug image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
import textwrap
from datetime import datetime

title = '''$session_title'''
session_content = ''

try:
    with open('$SESSION_LOG', 'r') as f:
        session_content = f.read()
except:
    session_content = 'No session log available'

# Calculate height needed
line_height = 11
char_width = 65
lines = []
for line in session_content.split('\n'):
    wrapped = textwrap.wrap(line, width=char_width) or ['']
    lines.extend(wrapped)

# Add separator at end
lines.append('=' * 60)
lines.append('')

total_height = (len(lines) + 2) * line_height + 30

# Create image
img = Image.new('L', (576, total_height), 255)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 9)
    title_font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 12)
except:
    font = ImageFont.load_default()
    title_font = font

y_pos = 10
draw.text((10, y_pos), title, font=title_font, fill=0)
y_pos += 20

for line in lines:
    draw.text((10, y_pos), line, font=font, fill=0)
    y_pos += line_height

img.save('/tmp/session_debug.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/session_debug.png
    
    # Clear session log for next run
    > "$SESSION_LOG"
}

# Function to print debug log to receipt printer
print_debug() {
    echo "=== Printing Debug Log ===" >> "$DEBUG_LOG"
    local title="$1"
    local max_lines="${2:-50}"
    
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
import textwrap

# Create title
title = '''${title:-DEBUG OUTPUT}'''
debug_content = ''
error_content = ''

try:
    with open('$DEBUG_LOG', 'r') as f:
        lines = f.readlines()[-$max_lines:]
        debug_content = ''.join(lines)
except:
    debug_content = 'Could not read debug log'

try:
    with open('$ERROR_LOG', 'r') as f:
        lines = f.readlines()[-20:]
        error_content = ''.join(lines)
except:
    error_content = ''

# Calculate height needed
line_height = 12
char_width = 60
debug_lines = []
for line in debug_content.split('\n'):
    wrapped = textwrap.wrap(line, width=char_width) or ['']
    debug_lines.extend(wrapped)

error_lines = []
if error_content:
    for line in error_content.split('\n'):
        wrapped = textwrap.wrap(line, width=char_width) or ['']
        error_lines.extend(wrapped)

total_height = (len(debug_lines) + len(error_lines) + 4) * line_height + 40

# Create image
img = Image.new('L', (576, total_height), 255)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 10)
    title_font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 14)
except:
    font = ImageFont.load_default()
    title_font = font

y_pos = 10
draw.text((10, y_pos), title, font=title_font, fill=0)
y_pos += 20

draw.text((10, y_pos), '=== DEBUG LOG ===', font=font, fill=0)
y_pos += line_height

for line in debug_lines:
    draw.text((10, y_pos), line, font=font, fill=0)
    y_pos += line_height

if error_lines:
    y_pos += line_height
    draw.text((10, y_pos), '=== ERRORS ===', font=font, fill=0)
    y_pos += line_height
    for line in error_lines:
        draw.text((10, y_pos), line, font=font, fill=0)
        y_pos += line_height

img.save('/tmp/debug_print.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/debug_print.png
    echo "Debug log printed" >> "$DEBUG_LOG"
}

# Function to log to both debug and session logs
log_both() {
    echo "$1" >> "$DEBUG_LOG"
    if [ "$VERBOSE_MODE" -eq 1 ]; then
        echo "$1" >> "$SESSION_LOG"
    fi
}

# Function to log errors to all logs
log_error() {
    echo "$1" >> "$ERROR_LOG"
    echo "$1" >> "$DEBUG_LOG"
    if [ "$VERBOSE_MODE" -eq 1 ]; then
        echo "ERROR: $1" >> "$SESSION_LOG"
    fi
}

# Function to print text as image
print_text() {
    echo "Printing text: $1" >> "$DEBUG_LOG"
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
    echo "Countdown: $number" >> "$DEBUG_LOG"
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

# Function to print CHEESE notification
print_cheese() {
    local photo_num=$1
    echo "CHEESE printed for photo $photo_num" >> "$DEBUG_LOG"
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('L', (576, 80), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 48)
    small_font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 14)
except:
    font = ImageFont.load_default()
    small_font = font

# Center CHEESE text
text = 'CHEESE!'
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
x_pos = (576 - text_width) // 2
draw.text((x_pos, 10), text, font=font, fill=0)

# Add photo number indicator
if '$photo_num' != '3':
    next_text = 'Get ready for next shot...'
    bbox = draw.textbbox((0, 0), next_text, font=small_font)
    text_width = bbox[2] - bbox[0]
    x_pos = (576 - text_width) // 2
    draw.text((x_pos, 60), next_text, font=small_font, fill=0)

img.save('/tmp/cheese.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/cheese.png >/dev/null 2>&1
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

# Signal handlers for graceful shutdown
cleanup_and_exit() {
    echo "=== Photo Booth Interrupted: $(date) ===" >> "$DEBUG_LOG"
    echo "Caught signal, printing debug output..." >> "$DEBUG_LOG"
    
    # Print debug output before exiting
    print_debug "INTERRUPTED - DEBUG OUTPUT"
    
    # Clean up temp files
    rm -f /tmp/text.png /tmp/count.png /tmp/sha*.png /tmp/sig.png /tmp/debug_print.png 2>/dev/null
    
    echo "=== Photo Booth Shutdown Complete ===" >> "$DEBUG_LOG"
    exit 0
}

# Error handler
handle_error() {
    local error_msg="$1"
    local error_code="${2:-1}"
    echo "ERROR: $error_msg" >> "$ERROR_LOG"
    echo "ERROR: $error_msg" >> "$DEBUG_LOG"
    print_debug "ERROR OCCURRED"
    if [ "$error_code" -ne 0 ]; then
        exit "$error_code"
    fi
}

# Set up signal traps
trap cleanup_and_exit SIGINT SIGTERM
trap 'handle_error "Script error on line $LINENO"' ERR

# Main loop
print_text "READY - PRESS ENTER TO TAKE PHOTO"
echo "Main loop started - waiting for user input" >> "$DEBUG_LOG"

while true; do
    # Clear session log for new session
    if [ "$VERBOSE_MODE" -eq 1 ]; then
        > "$SESSION_LOG"
        echo "=== SESSION START: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$SESSION_LOG"
    fi
    
    # Wait for ENTER
    log_both "Waiting for user input (ENTER)..."
    read
    log_both "User pressed ENTER at $(date)"
    
    # Countdown
    for i in 3 2 1; do
        print_countdown $i
        sleep 0.5
    done
    
    cd "$(eval echo $PHOTO_DIR)"
    log_both "Changed to photo directory: $(pwd)"
    
    # Take all 3 photos with different settings
    log_both "Taking photo 1..."
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo1.jpg --awb auto 2>> "$ERROR_LOG"; then
        log_error "Failed to capture photo1.jpg"
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            print_session_debug
        fi
        continue
    fi
    
    # Print CHEESE and give time to change expression
    print_cheese 1
    sleep 0.5
    
    log_both "Taking photo 2..."
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo2.jpg --awb auto --contrast 1.5 --sharpness 1.5 2>> "$ERROR_LOG"; then
        log_error "Failed to capture photo2.jpg"
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            print_session_debug
        fi
        continue
    fi
    
    # Print CHEESE and give time to change expression
    print_cheese 2
    sleep 0.5
    
    log_both "Taking photo 3..."
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo3.jpg --awb auto --ev -0.5 --contrast 1.2 2>> "$ERROR_LOG"; then
        log_error "Failed to capture photo3.jpg"
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            print_session_debug
        fi
        continue
    fi
    
    # Print final CHEESE
    print_cheese 3
    
    log_both "All photos captured successfully"
    
    # Check if photos exist and have size
    for photo in photo1.jpg photo2.jpg photo3.jpg; do
        if [ ! -f "$photo" ]; then
            log_error "Photo $photo does not exist"
            if [ "$VERBOSE_MODE" -eq 1 ]; then
                print_session_debug
            fi
            continue 2
        fi
        size=$(stat -c%s "$photo" 2>/dev/null || stat -f%z "$photo" 2>/dev/null)
        log_both "Photo $photo size: $size bytes"
        if [ "$size" -eq 0 ]; then
            log_error "Photo $photo is empty"
            if [ "$VERBOSE_MODE" -eq 1 ]; then
                print_session_debug
            fi
            continue 2
        fi
    done
    
    # Calculate SHAs
    log_both "Calculating SHA hashes..."
    SHA1=$(sha256sum photo1.jpg | cut -c1-24)
    SHA2=$(sha256sum photo2.jpg | cut -c1-24)
    SHA3=$(sha256sum photo3.jpg | cut -c1-24)
    log_both "SHA1: $SHA1"
    log_both "SHA2: $SHA2"
    log_both "SHA3: $SHA3"
    
    # Process photos for 3 different lighting scenarios
    # Strip 1: Low light optimization
    log_both "Processing photos for low light..."
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg lowlight 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo1.jpg for lowlight"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg lowlight 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo2.jpg for lowlight"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg lowlight 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo3.jpg for lowlight"
    fi
    
    # Strip 2: Auto/normal lighting
    log_both "Processing photos for auto lighting..."
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg auto 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo1.jpg for auto"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg auto 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo2.jpg for auto"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg auto 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo3.jpg for auto"
    fi
    
    # Strip 3: Bright light optimization
    log_both "Processing photos for bright light..."
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo1.jpg bright 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo1.jpg for bright"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo2.jpg bright 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo2.jpg for bright"
    fi
    if ! python "$PRINTER_LIB/image_processing/adaptive_dither.py" photo3.jpg bright 2>> "$ERROR_LOG"; then
        log_error "Failed to process photo3.jpg for bright"
    fi
    
    DATE=$(date '+%Y-%m-%d %H:%M')
    
    # Create SHA images
    create_sha_image "$SHA1" "/tmp/sha1.png"
    create_sha_image "$SHA2" "/tmp/sha2.png"
    create_sha_image "$SHA3" "/tmp/sha3.png"
    
    # Create signature
    create_signature "$DATE"
    
    # Print Strip 1: Low light versions with SHAs
    log_both "Printing strip 1 (low light)..."
    if ! python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_lowlight_receipt.jpg /tmp/sha1.png \
        photo2_lowlight_receipt.jpg /tmp/sha2.png \
        photo3_lowlight_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png 2>> "$ERROR_LOG"; then
        log_error "Failed to print strip 1"
    fi
    
    # Print Strip 2: Auto/normal versions with SHAs
    log_both "Printing strip 2 (auto)..."
    if ! python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_auto_receipt.jpg /tmp/sha1.png \
        photo2_auto_receipt.jpg /tmp/sha2.png \
        photo3_auto_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png 2>> "$ERROR_LOG"; then
        log_error "Failed to print strip 2"
    fi
    
    # Print Strip 3: Bright light versions with SHAs
    log_both "Printing strip 3 (bright)..."
    if ! python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_bright_receipt.jpg /tmp/sha1.png \
        photo2_bright_receipt.jpg /tmp/sha2.png \
        photo3_bright_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png 2>> "$ERROR_LOG"; then
        log_error "Failed to print strip 3"
    fi
    
    log_both "=== SESSION COMPLETE: $(date '+%Y-%m-%d %H:%M:%S') ==="
    
    # Print debug log if in verbose mode
    if [ "$VERBOSE_MODE" -eq 1 ]; then
        log_both "Printing session debug..."
        print_session_debug
    fi
    
    # Ready for next photo
    print_text "READY - PRESS ENTER TO TAKE PHOTO"
done