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
# Hard-code the photo_booth location since auto-detection is failing
PHOTO_BOOTH_ROOT="/home/pi/photo_booth"

# Verify it exists
if [ ! -d "$PHOTO_BOOTH_ROOT" ]; then
    echo "ERROR: photo_booth not found at $PHOTO_BOOTH_ROOT"
    echo "Searching for photo_booth directory..."
    find ~ -type d -name "photo_booth" 2>/dev/null | head -3
    exit 1
fi

# Set paths
PHOTO_DIR="${PHOTO_DIR:-~/pics}"
PRINTER_LIB="$PHOTO_BOOTH_ROOT"
VIRTUAL_ENV="${VIRTUAL_ENV:-~/myenv}"
DEBUG_LOG="/tmp/photo_booth_debug.log"
ERROR_LOG="/tmp/photo_booth_error.log"
SESSION_LOG="/tmp/photo_booth_session.log"

# Verify imgprint.py exists
if [ ! -f "$PRINTER_LIB/scripts/imgprint.py" ]; then
    echo "ERROR: imgprint.py not found at $PRINTER_LIB/scripts/imgprint.py"
    exit 1
fi

# Create photo directory if it doesn't exist
mkdir -p "$(eval echo $PHOTO_DIR)"

# Initialize debug logging - only redirect stderr to avoid interfering with prints
exec 2>> "$ERROR_LOG"

echo "=== Photo Booth Started: $(date) ===" >> "$DEBUG_LOG"
echo "PHOTO_DIR: $PHOTO_DIR" >> "$DEBUG_LOG"
echo "PRINTER_LIB: $PRINTER_LIB" >> "$DEBUG_LOG"
echo "VIRTUAL_ENV: $VIRTUAL_ENV" >> "$DEBUG_LOG"

# Activate virtual environment if exists
if [ -f "$VIRTUAL_ENV/bin/activate" ]; then
    source "$VIRTUAL_ENV/bin/activate"
    echo "Virtual environment activated" >> "$DEBUG_LOG"
fi

# Function to check printer status
check_printer() {
    echo "Checking for Epson TM-M50 printer..."
    
    # Check USB devices for Epson printer
    if lsusb | grep -i "epson\|04b8" > /dev/null 2>&1; then
        echo "Found Epson USB device" >> "$DEBUG_LOG"
        echo "✓ Epson printer detected via USB"
        
        # Check if printer device exists
        if [ -c /dev/usb/lp0 ] || [ -c /dev/usb/lp1 ] || [ -c /dev/usblp0 ]; then
            echo "Printer device node found" >> "$DEBUG_LOG"
            return 0
        else
            echo "WARNING: Epson detected but no device node (/dev/usb/lp*)" >> "$DEBUG_LOG"
            echo "! Printer detected but device not ready"
            echo "  Try: sudo modprobe usblp"
            return 1
        fi
    else
        echo "ERROR: No Epson printer detected" >> "$DEBUG_LOG"
        echo "✗ No Epson TM-M50 printer found!"
        echo "  Please check:"
        echo "  1. Printer is powered on"
        echo "  2. USB cable is connected"
        echo "  3. Try unplugging and reconnecting USB"
        return 1
    fi
}

# Function to test printer with small print
test_printer() {
    echo "Testing printer connection..."
    
    # Create test image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('L', (576, 40), 255)
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 12)
except:
    font = ImageFont.load_default()
draw.text((10, 10), 'Printer Test OK - $(date +%H:%M:%S)', font=font, fill=0)
img.save('/tmp/test_print.png')
"
    
    # Check if test image was created
    if [ ! -f /tmp/test_print.png ]; then
        echo "✗ Failed to create test image"
        return 1
    fi
    
    # Try to print with full error output
    echo "Attempting to print test image..."
    
    if python "$PRINTER_LIB/scripts/imgprint.py" /tmp/test_print.png 2>&1; then
        echo "✓ Printer test successful" 
        echo "Printer test successful" >> "$DEBUG_LOG"
        return 0
    else
        PRINT_ERROR=$?
        echo "✗ Printer test failed (exit code: $PRINT_ERROR)"
        echo "Printer test failed with code $PRINT_ERROR" >> "$DEBUG_LOG"
        
        # Try alternative print methods
        echo "Checking printer device nodes..."
        ls -la /dev/usb/lp* 2>/dev/null || echo "No /dev/usb/lp* devices found"
        ls -la /dev/usblp* 2>/dev/null || echo "No /dev/usblp* devices found"
        
        # Check if we can write directly to printer
        if [ -c /dev/usb/lp0 ]; then
            echo "Found /dev/usb/lp0 - checking write permission..."
            if [ -w /dev/usb/lp0 ]; then
                echo "Write permission OK"
            else
                echo "No write permission - may need sudo or user group adjustment"
                echo "Try: sudo usermod -a -G lp $USER"
            fi
        fi
        
        return 1
    fi
}

# Initialize printer check flag
PRINTER_CHECKED=0
PRINTER_READY=0

# Function to ensure printer is ready (called on first photo)
ensure_printer_ready() {
    if [ $PRINTER_CHECKED -eq 1 ] && [ $PRINTER_READY -eq 1 ]; then
        return 0
    fi
    
    echo ""
    echo "=== CHECKING PRINTER CONNECTION ==="
    echo ""
    
    local MAX_RETRIES=3
    local RETRY_COUNT=0
    
    while [ $PRINTER_READY -eq 0 ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if check_printer; then
            if test_printer; then
                PRINTER_READY=1
                PRINTER_CHECKED=1
                echo ""
                echo "=== PRINTER READY ==="
                echo ""
                return 0
            else
                echo ""
                echo "Printer found but not responding. Retrying in 3 seconds..."
                sleep 3
            fi
        else
            echo ""
            echo "Retry $((RETRY_COUNT + 1)) of $MAX_RETRIES"
            echo "Waiting 5 seconds before retry..."
            echo ""
            sleep 5
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    if [ $PRINTER_READY -eq 0 ]; then
        echo ""
        echo "=== PRINTER NOT AVAILABLE ==="
        echo ""
        echo "Troubleshooting steps:"
        echo "1. Check printer power and LED status"
        echo "2. Unplug USB cable from Pi, wait 5 seconds, reconnect"
        echo "3. If camera is using USB, try a different USB port"
        echo "4. Run: lsusb | grep -i epson"
        echo "5. Run: ls -la /dev/usb/"
        echo ""
        
        # Wait for user to fix it
        while [ $PRINTER_READY -eq 0 ]; do
            echo "Press ENTER to retry printer detection..."
            read
            if check_printer && test_printer; then
                PRINTER_READY=1
                PRINTER_CHECKED=1
                echo "✓ Printer now ready!"
                return 0
            fi
        done
    fi
}

# Function to print processing log strip (for verbose mode)
print_processing_log() {
    local title="PROCESSING LOG $(date '+%H:%M:%S')"
    
    # Create processing log image with all the steps
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
import textwrap
from datetime import datetime

title = '''$title'''
processing_content = ''

try:
    with open('$SESSION_LOG', 'r') as f:
        # Read all processing-related lines
        lines = f.readlines()
        processing_lines = []
        for line in lines:
            # Filter for processing-related messages
            if any(keyword in line for keyword in ['Taking photo', 'captured', 'SHA', 'Processing', 'size:', 'Calculating']):
                processing_lines.append(line.strip())
        processing_content = '\n'.join(processing_lines)
except:
    processing_content = 'No processing log available'

# Calculate height needed
line_height = 10
char_width = 70
lines = []
for line in processing_content.split('\n'):
    wrapped = textwrap.wrap(line, width=char_width) or ['']
    lines.extend(wrapped)

# Add cut line at end
lines.append('')
lines.append('-' * 70)
lines.append('CUT HERE')
lines.append('-' * 70)

total_height = (len(lines) + 2) * line_height + 35

# Create image
img = Image.new('L', (576, total_height), 255)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 8)
    title_font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 11)
except:
    font = ImageFont.load_default()
    title_font = font

y_pos = 10
# Center the title
bbox = draw.textbbox((0, 0), title, font=title_font)
text_width = bbox[2] - bbox[0]
x_pos = (576 - text_width) // 2
draw.text((x_pos, y_pos), title, font=title_font, fill=0)
y_pos += 20

for line in lines:
    if 'CUT HERE' in line:
        # Center the cut line
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x_pos = (576 - text_width) // 2
        draw.text((x_pos, y_pos), line, font=font, fill=0)
    else:
        draw.text((10, y_pos), line, font=font, fill=0)
    y_pos += line_height

img.save('/tmp/processing_log.png')
"
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/processing_log.png
}

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

# Function to print error alert to receipt
print_error_alert() {
    local error_title="$1"
    local error_details="$2"
    echo "PRINTING ERROR ALERT: $error_title" >> "$DEBUG_LOG"
    echo "ERROR ALERT: $error_title"  # Echo to console
    
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
import textwrap
from datetime import datetime

title = '''ERROR ALERT'''
error_msg = '''$error_title'''
details = '''$error_details'''
timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# Calculate height
lines = []
lines.append('!' * 50)
lines.append('')
lines.append('ERROR ALERT')
lines.append('')
lines.extend(textwrap.wrap(error_msg, width=45))
lines.append('')
if details:
    lines.extend(textwrap.wrap(details, width=45))
    lines.append('')
lines.append(timestamp)
lines.append('!' * 50)

line_height = 14
total_height = len(lines) * line_height + 20

# Create image
img = Image.new('L', (576, total_height), 255)
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 12)
    title_font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 16)
except:
    font = ImageFont.load_default()
    title_font = font

y_pos = 10
for i, line in enumerate(lines):
    if 'ERROR ALERT' in line:
        # Center the title
        bbox = draw.textbbox((0, 0), line, font=title_font)
        text_width = bbox[2] - bbox[0]
        x_pos = (576 - text_width) // 2
        draw.text((x_pos, y_pos), line, font=title_font, fill=0)
    elif '!' * 10 in line:
        # Center separator lines
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x_pos = (576 - text_width) // 2
        draw.text((x_pos, y_pos), line, font=font, fill=0)
    else:
        draw.text((40, y_pos), line, font=font, fill=0)
    y_pos += line_height

img.save('/tmp/error_alert.png')
"
    # Print the error alert
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/error_alert.png 2>&1
}

# Function to print text as image
print_text() {
    echo "Printing text: $1" >> "$DEBUG_LOG"
    echo "Printing text: $1"  # Also echo to console
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
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/text.png
}

# Function to print countdown
print_countdown() {
    local number=$1
    echo "Countdown: $number" >> "$DEBUG_LOG"
    echo "Countdown: $number"  # Also echo to console
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
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/count.png
}

# Function to print CHEESE notification
print_cheese() {
    local photo_num=$1
    echo "CHEESE printed for photo $photo_num" >> "$DEBUG_LOG"
    echo "CHEESE! Photo $photo_num captured"  # Echo to console
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
    python "$PRINTER_LIB/scripts/imgprint.py" /tmp/cheese.png
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
echo ""
echo "==================================="
echo "    PHOTO BOOTH READY TO START"
echo "==================================="
echo ""
echo "Press ENTER to take photos"
echo "(Printer will be checked on first use)"
echo ""
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
    
    # Always give time to swap USB and position people
    echo ""
    echo "==================================="
    echo "     PREPARE FOR PHOTOS!"
    echo "==================================="
    echo ""
    echo "You have 5 seconds to:"
    echo "1. Swap camera to printer USB"
    echo "2. Position people for photo"
    echo ""
    for i in 5 4 3 2 1; do
        echo "  Starting in $i..."
        sleep 1
    done
    echo ""
    
    # Check printer on first run or if it was disconnected
    if [ $PRINTER_CHECKED -eq 0 ] || [ $PRINTER_READY -eq 0 ]; then
        ensure_printer_ready
    fi
    
    # Countdown
    for i in 3 2 1; do
        print_countdown $i
        sleep 0.5
    done
    
    cd "$(eval echo $PHOTO_DIR)"
    log_both "Changed to photo directory: $(pwd)"
    
    # Delete old photos to ensure we get new ones
    rm -f photo1.jpg photo2.jpg photo3.jpg
    rm -f photo*_*_receipt.jpg
    log_both "Cleared old photos"
    
    # Reset camera module to clear any bad state
    echo "Resetting camera module..."
    # Try to reset V4L2 devices (only if we have sudo access)
    if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
        sudo modprobe -r bcm2835-v4l2 2>/dev/null || true
        sudo modprobe -r bcm2835-isp 2>/dev/null || true
        sleep 1
        sudo modprobe bcm2835-v4l2 2>/dev/null || true
        sudo modprobe bcm2835-isp 2>/dev/null || true
    else
        echo "Skipping module reset (no sudo access)"
    fi
    
    # Kill any stuck camera processes (these don't need sudo)
    pkill -f rpicam 2>/dev/null || true
    pkill -f libcamera 2>/dev/null || true
    sleep 1
    
    # Add delay for camera to initialize after reset
    echo "Initializing camera..."
    sleep 3
    
    # Take all 3 photos with different settings
    log_both "Taking photo 1..."
    echo "Taking photo 1..."  # Echo to console
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo1.jpg --awb auto 2>&1 | tee /tmp/camera_error.txt; then
        CAMERA_ERROR=$(cat /tmp/camera_error.txt)
        echo "ERROR: Failed to capture photo1.jpg - check camera connection!"
        log_error "Failed to capture photo1.jpg: $CAMERA_ERROR"
        print_error_alert "CAMERA FAILURE - PHOTO 1" "$CAMERA_ERROR"
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            print_session_debug
        fi
        continue
    fi
    
    # Print CHEESE and give time to change expression
    print_cheese 1
    sleep 0.5
    
    log_both "Taking photo 2..."
    echo "Taking photo 2..."  # Echo to console
    sleep 1  # Longer delay between shots to let camera recover
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo2.jpg --awb auto --contrast 1.5 --sharpness 1.5 2>&1 | tee /tmp/camera_error.txt; then
        CAMERA_ERROR=$(cat /tmp/camera_error.txt)
        echo "ERROR: Failed to capture photo2.jpg - check camera connection!"
        log_error "Failed to capture photo2.jpg: $CAMERA_ERROR"
        print_error_alert "CAMERA FAILURE - PHOTO 2" "$CAMERA_ERROR"
        if [ "$VERBOSE_MODE" -eq 1 ]; then
            print_session_debug
        fi
        continue
    fi
    
    # Print CHEESE and give time to change expression
    print_cheese 2
    sleep 0.5
    
    log_both "Taking photo 3..."
    echo "Taking photo 3..."  # Echo to console
    sleep 1  # Longer delay between shots to let camera recover
    if ! rpicam-jpeg --nopreview --immediate --timeout 1000 --output photo3.jpg --awb auto --ev -0.5 --contrast 1.2 2>&1 | tee /tmp/camera_error.txt; then
        CAMERA_ERROR=$(cat /tmp/camera_error.txt)
        echo "ERROR: Failed to capture photo3.jpg - check camera connection!"
        log_error "Failed to capture photo3.jpg: $CAMERA_ERROR"
        print_error_alert "CAMERA FAILURE - PHOTO 3" "$CAMERA_ERROR"
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
            print_error_alert "PHOTO FILE MISSING" "File $photo was not created. Camera may have disconnected or failed."
            if [ "$VERBOSE_MODE" -eq 1 ]; then
                print_session_debug
            fi
            continue 2
        fi
        size=$(stat -c%s "$photo" 2>/dev/null || stat -f%z "$photo" 2>/dev/null)
        log_both "Photo $photo size: $size bytes"
        if [ "$size" -eq 0 ]; then
            log_error "Photo $photo is empty"
            print_error_alert "PHOTO FILE EMPTY" "File $photo has 0 bytes. Camera capture failed."
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
    
    # Process photos - ONLY LOW LIGHT (first strip only)
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
    
    DATE=$(date '+%Y-%m-%d %H:%M')
    
    # Create SHA images
    create_sha_image "$SHA1" "/tmp/sha1.png"
    create_sha_image "$SHA2" "/tmp/sha2.png"
    create_sha_image "$SHA3" "/tmp/sha3.png"
    
    # Create signature
    create_signature "$DATE"
    
    # Print processing log strip in verbose mode (before photos)
    if [ "$VERBOSE_MODE" -eq 1 ]; then
        log_both "Printing processing log strip..."
        print_processing_log
    fi
    
    # Print ONLY Strip 1: Low light versions with SHAs
    log_both "Printing photo strip..."
    if ! python "$PRINTER_LIB/scripts/imgprint.py" \
        photo1_lowlight_receipt.jpg /tmp/sha1.png \
        photo2_lowlight_receipt.jpg /tmp/sha2.png \
        photo3_lowlight_receipt.jpg /tmp/sha3.png \
        /tmp/sig.png 2>> "$ERROR_LOG"; then
        log_error "Failed to print strip"
    fi
    
    log_both "=== SESSION COMPLETE: $(date '+%Y-%m-%d %H:%M:%S') ==="
    
    # Give time to swap back to camera if needed
    if [ $PRINTER_CHECKED -eq 1 ]; then
        echo ""
        echo "==================================="
        echo "     PHOTOS PRINTED!"
        echo "==================================="
        echo ""
        echo "You can now swap back to camera USB if needed"
        echo "Waiting 3 seconds before ready..."
        sleep 3
    fi
    
    # Ready for next photo
    print_text "READY - PRESS ENTER TO TAKE PHOTO"
done