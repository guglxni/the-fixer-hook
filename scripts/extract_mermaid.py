#!/usr/bin/env python3
"""Extract mermaid diagrams from markdown files and convert to PNG."""

import re
import os
import subprocess
import glob

DOCS_DIR = "docs"
OUTPUT_DIR = "docs/diagrams"

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Get all markdown files
md_files = glob.glob(f"{DOCS_DIR}/*.md")

total_diagrams = 0

for mdfile in md_files:
    filename = os.path.basename(mdfile).replace(".md", "")
    
    with open(mdfile, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find all mermaid blocks
    pattern = r'```mermaid\n(.*?)```'
    matches = re.findall(pattern, content, re.DOTALL)
    
    for i, diagram in enumerate(matches):
        diagram_name = f"{filename}_{i+1}"
        mmd_file = os.path.join(OUTPUT_DIR, f"{diagram_name}.mmd")
        png_file = os.path.join(OUTPUT_DIR, f"{diagram_name}.png")
        
        # Write mermaid file
        with open(mmd_file, 'w', encoding='utf-8') as f:
            f.write(diagram.strip())
        
        # Convert to PNG
        try:
            result = subprocess.run(
                ['mmdc', '-i', mmd_file, '-o', png_file, '-b', 'white', '-s', '2'],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                print(f"Created: {png_file}")
                total_diagrams += 1
            else:
                print(f"Error creating {png_file}: {result.stderr}")
        except Exception as e:
            print(f"Exception for {png_file}: {e}")
    
    if matches:
        print(f"Processed {len(matches)} diagrams from {filename}")

print(f"\nTotal diagrams created: {total_diagrams}")
print(f"Output directory: {OUTPUT_DIR}")
