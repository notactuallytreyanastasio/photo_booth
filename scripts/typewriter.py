#!/usr/bin/env python3
"""
Receipt Paper Typewriter
Live typing experience that prints to thermal receipt printer
"""

import sys
import os
from PIL import Image, ImageDraw, ImageFont
import subprocess
import time

# Configuration
RECEIPT_WIDTH = 576  # Standard receipt printer width in pixels
FONT_SIZE = 14       # Bigger font to use full width
LINE_HEIGHT = 16     # Very tight line spacing
MARGIN = 5           # Minimal margin to use full width

class ReceiptTypewriter:
    def __init__(self):
        self.printer_lib = "/home/pi/photo_booth"
        self.buffer = []  # Buffer lines until double-enter
        self.last_was_empty = False  # Track double-enter
        
        # Try to load a nice monospace font
        try:
            self.font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', FONT_SIZE)
        except:
            try:
                self.font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', FONT_SIZE)
            except:
                self.font = ImageFont.load_default()
        
        print("\n" + "="*64)
        print("    RECEIPT TYPEWRITER")
        print("="*64)
        print("\nType and press ENTER for new lines.")
        print("Press ENTER twice to print the section.")
        print("Press Ctrl+C to finish.\n")
        print("Line width guide (64 characters):")
        print("1234567890" * 6 + "1234")  # 64 character ruler
        print("-"*64 + "\n")
    
    def print_buffer(self):
        """Print all buffered lines without cutting"""
        if not self.buffer:
            return
            
        # Calculate height for all lines (very tight)
        total_height = len(self.buffer) * LINE_HEIGHT + 5
        
        # Create image for the lines
        img = Image.new('L', (RECEIPT_WIDTH, total_height), 255)
        draw = ImageDraw.Draw(img)
        
        # Draw each line with tight spacing
        y_pos = 2
        for line in self.buffer:
            # Handle long lines by wrapping
            if line:
                # Calculate actual width with bigger font - now allowing more chars
                max_chars = 64  # 16 more characters (was 48)
                while len(line) > max_chars:
                    # Find last space before limit
                    wrap_point = line[:max_chars].rfind(' ')
                    if wrap_point <= 0:
                        wrap_point = max_chars
                    
                    draw.text((MARGIN, y_pos), line[:wrap_point], font=self.font, fill=0)
                    y_pos += LINE_HEIGHT
                    line = line[wrap_point:].lstrip()
                
            # Draw remaining or full line
            draw.text((MARGIN, y_pos), line, font=self.font, fill=0)
            y_pos += LINE_HEIGHT
        
        # Save and print
        temp_img = "/tmp/typewriter_line.png"
        img.save(temp_img)
        
        try:
            # Use imgprint.py - it should NOT cut between lines
            subprocess.run(
                ["python", f"{self.printer_lib}/scripts/imgprint.py", temp_img],
                capture_output=True,
                text=True,
                timeout=5
            )
            # Clear buffer after printing
            self.buffer = []
            print("[Printed]")
        except subprocess.TimeoutExpired:
            print("[Printer timeout]")
        except Exception as e:
            print(f"[Print error: {e}]")
    
    def run(self):
        """Main loop - collect lines, print on double-enter"""
        try:
            while True:
                # Get a line of input
                line = input()
                
                # Check for double-enter (print trigger)
                if line == "" and self.last_was_empty:
                    # Double enter - print everything
                    if self.buffer:
                        self.print_buffer()
                    self.last_was_empty = False
                else:
                    # Add line to buffer (including empty lines)
                    self.buffer.append(line)
                    self.last_was_empty = (line == "")
                
        except KeyboardInterrupt:
            # Print any remaining buffer
            if self.buffer:
                print("\n[Printing remaining text...]")
                self.print_buffer()
            
            # Print footer
            print("[Printing footer...]")
            footer_lines = [
                "",
                "=" * 50,
                f"END - {time.strftime('%Y-%m-%d %H:%M')}",
                "=" * 50,
                "",
                ""  # Extra space for tear-off
            ]
            
            self.buffer = footer_lines
            self.print_buffer()
            print("\n[Letter complete]")
        
        except EOFError:
            # Handle Ctrl+D - print current buffer
            if self.buffer:
                self.print_buffer()
            print("\n[Buffer printed]")

def main():
    """Run the typewriter"""
    typewriter = ReceiptTypewriter()
    typewriter.run()

if __name__ == "__main__":
    main()