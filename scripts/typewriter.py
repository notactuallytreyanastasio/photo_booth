#!/usr/bin/env python3
"""
Receipt Paper Typewriter
Live typing experience that prints to thermal receipt printer
"""

import sys
import os
import termios
import tty
from PIL import Image, ImageDraw, ImageFont
import textwrap
import subprocess
from pathlib import Path

# Configuration
RECEIPT_WIDTH = 576  # Standard receipt printer width in pixels
CHAR_WIDTH = 48      # Approximate characters per line with monospace font
FONT_SIZE = 14       # Font size for readability
LINE_HEIGHT = 20     # Pixels between lines
MARGIN = 10          # Left/right margin

class ReceiptTypewriter:
    def __init__(self):
        self.current_line = ""
        self.printer_lib = "/home/pi/photo_booth"
        
        # Try to load a nice monospace font
        try:
            self.font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', FONT_SIZE)
        except:
            try:
                self.font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', FONT_SIZE)
            except:
                self.font = ImageFont.load_default()
        
        # Terminal settings for raw input
        self.old_settings = None
        
        print("\n" + "="*50)
        print("    RECEIPT TYPEWRITER")
        print("="*50)
        print("\nStart typing! Your text will print when you:")
        print("  • Press ENTER for a new line")
        print("  • Reach the end of a line (auto-wrap)")
        print("  • Press Ctrl+C to exit")
        print("\n" + "-"*50 + "\n")
        
    def print_line(self, text):
        """Print a single line to the receipt printer"""
        if not text and text != "":  # Skip if None, but allow empty string
            return
            
        # Create image for the line
        img_height = LINE_HEIGHT + 5
        img = Image.new('L', (RECEIPT_WIDTH, img_height), 255)
        draw = ImageDraw.Draw(img)
        
        # Draw the text
        draw.text((MARGIN, 2), text, font=self.font, fill=0)
        
        # Save temporary image
        temp_img = "/tmp/typewriter_line.png"
        img.save(temp_img)
        
        # Print using imgprint.py
        try:
            subprocess.run(
                ["python", f"{self.printer_lib}/scripts/imgprint.py", temp_img],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            print("\n[Printer timeout - check connection]")
        except Exception as e:
            print(f"\n[Print error: {e}]")
    
    def get_char_width(self, text):
        """Calculate how many characters fit on a line"""
        # Create a test image to measure text width
        test_img = Image.new('L', (RECEIPT_WIDTH, 30), 255)
        test_draw = ImageDraw.Draw(test_img)
        
        # Measure the text
        bbox = test_draw.textbbox((0, 0), text, font=self.font)
        text_width = bbox[2] - bbox[0]
        
        return text_width < (RECEIPT_WIDTH - 2 * MARGIN)
    
    def handle_character(self, char):
        """Process each character as it's typed"""
        if char == '\r' or char == '\n':  # Enter pressed
            # Print current line and start new one
            self.print_line(self.current_line)
            print(self.current_line)  # Echo to screen
            self.current_line = ""
            
        elif char == '\x7f' or char == '\b':  # Backspace
            if self.current_line:
                self.current_line = self.current_line[:-1]
                # Update display
                sys.stdout.write('\r' + ' ' * (len(self.current_line) + 10) + '\r')
                sys.stdout.write(self.current_line)
                sys.stdout.flush()
                
        elif char == '\x03':  # Ctrl+C
            raise KeyboardInterrupt
            
        elif ord(char) >= 32:  # Printable character
            # Check if adding this character would exceed line width
            test_line = self.current_line + char
            
            if not self.get_char_width(test_line):
                # Line would be too long, wrap it
                # Try to wrap at last space for word wrapping
                last_space = self.current_line.rfind(' ')
                
                if last_space > 0 and last_space > len(self.current_line) - 20:
                    # Wrap at word boundary
                    print_text = self.current_line[:last_space]
                    self.print_line(print_text)
                    print(print_text)  # Echo wrapped line
                    self.current_line = self.current_line[last_space+1:] + char
                    sys.stdout.write('\n' + self.current_line)
                else:
                    # No good wrap point, wrap at character limit
                    self.print_line(self.current_line)
                    print(self.current_line)  # Echo full line
                    self.current_line = char
                    sys.stdout.write('\n' + char)
            else:
                # Add character normally
                self.current_line += char
                sys.stdout.write(char)
            
            sys.stdout.flush()
    
    def run(self):
        """Main typewriter loop"""
        try:
            # Set terminal to raw mode for immediate character input
            self.old_settings = termios.tcgetattr(sys.stdin)
            tty.setraw(sys.stdin.fileno())
            
            while True:
                char = sys.stdin.read(1)
                self.handle_character(char)
                
        except KeyboardInterrupt:
            # Print any remaining text
            if self.current_line:
                self.print_line(self.current_line)
                print(self.current_line)
            
            # Print footer
            self.print_line("-" * 40)
            self.print_line("END OF MESSAGE")
            self.print_line("")  # Extra space for tear-off
            
            print("\n\n[Typewriter session ended]")
            
        finally:
            # Restore terminal settings
            if self.old_settings:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)
            print()  # Final newline

def main():
    """Run the typewriter"""
    typewriter = ReceiptTypewriter()
    typewriter.run()

if __name__ == "__main__":
    main()