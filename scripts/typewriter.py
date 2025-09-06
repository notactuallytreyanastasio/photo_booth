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
import time

# Configuration
RECEIPT_WIDTH = 576  # Standard receipt printer width in pixels
CHAR_WIDTH = 48      # Approximate characters per line with monospace font
FONT_SIZE = 11       # Smaller font for more content
LINE_HEIGHT = 13     # Tighter line spacing
MARGIN = 10          # Left/right margin
BATCH_LINES = 5      # Print every N lines to reduce cutting

class ReceiptTypewriter:
    def __init__(self):
        self.current_line = ""
        self.line_buffer = []  # Buffer to collect lines before printing
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
        print("\nStart typing! Your text will print continuously.")
        print("  • Press ENTER for new paragraphs")
        print("  • Text auto-wraps at line end")
        print("  • Press Ctrl+D to print current buffer")
        print("  • Press Ctrl+C to finish and exit")
        print("\n" + "-"*50 + "\n")
        
    def flush_buffer(self):
        """Print all buffered lines together"""
        if not self.line_buffer:
            return
            
        # Calculate total height needed
        total_height = len(self.line_buffer) * LINE_HEIGHT + 10
        
        # Create single image for all buffered lines
        img = Image.new('L', (RECEIPT_WIDTH, total_height), 255)
        draw = ImageDraw.Draw(img)
        
        # Draw all lines
        y_pos = 5
        for line in self.line_buffer:
            draw.text((MARGIN, y_pos), line, font=self.font, fill=0)
            y_pos += LINE_HEIGHT
        
        # Save temporary image
        temp_img = "/tmp/typewriter_batch.png"
        img.save(temp_img)
        
        # Print using imgprint.py
        try:
            subprocess.run(
                ["python", f"{self.printer_lib}/scripts/imgprint.py", temp_img],
                capture_output=True,
                text=True,
                timeout=5
            )
            # Clear buffer after successful print
            self.line_buffer = []
        except subprocess.TimeoutExpired:
            print("\n[Printer timeout - check connection]")
        except Exception as e:
            print(f"\n[Print error: {e}]")
    
    def add_line(self, text):
        """Add a line to the buffer and print if buffer is full"""
        self.line_buffer.append(text)
        
        # Print batch when we have enough lines
        if len(self.line_buffer) >= BATCH_LINES:
            self.flush_buffer()
    
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
            # Add current line to buffer and start new one
            self.add_line(self.current_line)
            print(self.current_line)  # Echo to screen
            self.current_line = ""
            
        elif char == '\x04':  # Ctrl+D - flush buffer
            if self.current_line:
                self.add_line(self.current_line)
                print(self.current_line)
                self.current_line = ""
                sys.stdout.write('\n')
            self.flush_buffer()
            print("[Buffer printed]")
            
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
                    self.add_line(print_text)
                    print(print_text)  # Echo wrapped line
                    self.current_line = self.current_line[last_space+1:] + char
                    sys.stdout.write('\n' + self.current_line)
                else:
                    # No good wrap point, wrap at character limit
                    self.add_line(self.current_line)
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
            # Add any remaining text to buffer
            if self.current_line:
                self.add_line(self.current_line)
                print("\n" + self.current_line)
            
            # Add footer to buffer
            self.add_line("")
            self.add_line("-" * 45)
            self.add_line("END OF MESSAGE - " + time.strftime("%Y-%m-%d %H:%M"))
            self.add_line("-" * 45)
            self.add_line("")  # Extra space for tear-off
            
            # Flush everything
            self.flush_buffer()
            
            print("\n\n[Letter complete and printed]")
            
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