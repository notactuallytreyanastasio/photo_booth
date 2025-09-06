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
FONT_SIZE = 11       # Smaller font for more content
LINE_HEIGHT = 13     # Tighter line spacing
MARGIN = 10          # Left/right margin

class ReceiptTypewriter:
    def __init__(self):
        self.printer_lib = "/home/pi/photo_booth"
        self.all_lines = []  # Keep track of everything typed
        
        # Try to load a nice monospace font
        try:
            self.font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', FONT_SIZE)
        except:
            try:
                self.font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', FONT_SIZE)
            except:
                self.font = ImageFont.load_default()
        
        print("\n" + "="*50)
        print("    RECEIPT TYPEWRITER")
        print("="*50)
        print("\nType and press ENTER to print each line.")
        print("Lines print immediately without cutting.")
        print("Press Ctrl+C to finish.\n")
        print("-"*50 + "\n")
    
    def print_lines(self, lines):
        """Print one or more lines without cutting"""
        if not lines:
            return
            
        # Calculate height for all lines
        total_height = len(lines) * LINE_HEIGHT + 10
        
        # Create image for the lines
        img = Image.new('L', (RECEIPT_WIDTH, total_height), 255)
        draw = ImageDraw.Draw(img)
        
        # Draw each line
        y_pos = 5
        for line in lines:
            # Handle long lines by wrapping
            if line:
                # Simple character-based wrapping
                max_chars = 65  # Approximate chars that fit
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
            # Use imgprint.py without cutting
            subprocess.run(
                ["python", f"{self.printer_lib}/scripts/imgprint.py", temp_img],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            print("[Printer timeout]")
        except Exception as e:
            print(f"[Print error: {e}]")
    
    def run(self):
        """Main loop - simple line-by-line input"""
        try:
            while True:
                # Get a line of input (normal Python input)
                line = input()
                
                # Store it
                self.all_lines.append(line)
                
                # Print immediately (just this line, no cut)
                self.print_lines([line])
                
        except KeyboardInterrupt:
            # Print footer
            print("\n[Finishing letter...]")
            
            footer = [
                "",
                "-" * 45,
                f"END - {time.strftime('%Y-%m-%d %H:%M')}",
                "-" * 45,
                "",
                ""  # Extra space for tear-off
            ]
            
            self.print_lines(footer)
            print("\n[Letter complete]")
        
        except EOFError:
            # Handle Ctrl+D
            print("\n[Letter ended]")

def main():
    """Run the typewriter"""
    typewriter = ReceiptTypewriter()
    typewriter.run()

if __name__ == "__main__":
    main()