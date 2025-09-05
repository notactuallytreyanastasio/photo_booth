"""
Custom receipt printer for full-width, no-margin printing
"""

import sys
import os

try:
    from .receipt_printer import ReceiptPrinter
except ImportError:
    from receipt_printer import ReceiptPrinter
from PIL import Image
import subprocess
from typing import Union
from pathlib import Path

class FullWidthPrinter(ReceiptPrinter):
    """Receipt printer with full-width printing and no margins"""
    
    def __init__(self, printer_name: str = "EPSON_TM_m50"):
        super().__init__(printer_name)
        # TM-m50 standard width for 80mm paper
        # 576 pixels is the standard ESC/POS width for 80mm thermal printers
        # This is the ACTUAL hardware capability
        self.image_width = 576  # Standard thermal printer width
        
    def image_to_esc_pos(self, img: Image.Image) -> bytes:
        """
        Convert image to ESC/POS with LEFT alignment (no margins)
        """
        if img.mode != '1':
            raise ValueError("Image must be 1-bit (mode '1')")
        
        width, height = img.size
        
        # Ensure width is multiple of 8
        if width % 8 != 0:
            new_width = (width // 8 + 1) * 8
            new_img = Image.new('1', (new_width, height), 255)
            new_img.paste(img, (0, 0))
            img = new_img
            width = new_width
        
        # Initialize with LEFT alignment for no margins
        command = self.INIT + self.ALIGN_LEFT  # Changed from CENTER to LEFT
        
        # Set line spacing to 0 for continuous image
        command += self.ESC + b'3' + b'\x00'  # Set line spacing to 0
        
        # Use GS v 0 command (raster bit image)
        m = 0  # Normal size
        xL = (width // 8) % 256
        xH = (width // 8) // 256
        yL = height % 256
        yH = height // 256
        
        command += self.GS + b'v0' + bytes([m, xL, xH, yL, yH])
        
        # Convert image to bytes
        pixels = img.load()
        for y in range(height):
            row_data = bytearray()
            for x in range(0, width, 8):
                byte = 0
                for bit in range(8):
                    if x + bit < width:
                        # Invert: black pixels (0) should print
                        if pixels[x + bit, y] == 0:
                            byte |= (1 << (7 - bit))
                row_data.append(byte)
            command += bytes(row_data)
        
        # Reset line spacing
        command += self.ESC + b'2'  # Reset to default line spacing
        
        # No extra line feeds - cut immediately after image
        
        return command
    
    def print_image(self, image_path: Union[str, Path, Image.Image],
                   width: int = None,
                   dither_method: str = 'floyd_steinberg',
                   threshold: int = 128,
                   add_cuts: bool = True) -> bool:
        """
        Print image with minimal white space before cut
        """
        try:
            # Process the image
            processed_img = self.process_image(
                image_path, width, dither_method, threshold
            )
            
            # Convert to ESC/POS commands
            image_data = self.image_to_esc_pos(processed_img)
            
            # Add minimal paper feed and optional cut
            if add_cuts:
                # Polaroid-style: 5 line feeds for white border at bottom
                image_data += self.FEED_LINE * 5 + self.CUT_PAPER
            else:
                # Just 2 line feeds for spacing between images
                image_data += self.FEED_LINE * 2
            
            # Send to printer
            process = subprocess.Popen(
                ['lp', '-d', self.printer_name, '-o', 'raw'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            stdout, stderr = process.communicate(image_data)
            
            if process.returncode == 0:
                print(f"Image printed successfully: {stdout.decode().strip()}")
                return True
            else:
                print(f"Printing failed: {stderr.decode().strip()}")
                return False
                
        except Exception as e:
            print(f"Error printing image: {e}")
            return False