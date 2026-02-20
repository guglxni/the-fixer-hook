#!/bin/bash
# Extract mermaid diagrams from markdown files and convert to PNG

DOCS_DIR="docs"
OUTPUT_DIR="docs/diagrams"

mkdir -p "$OUTPUT_DIR"

# Process each markdown file
for mdfile in "$DOCS_DIR"/*.md; do
    filename=$(basename "$mdfile" .md)
    
    # Extract mermaid blocks and convert to PNG
    awk '
    /^```mermaid$/ { in_mermaid=1; diagram_name=""; count++; next }
    in_mermaid && /^```$/ { 
        in_mermaid=0
        print "" > outfile
        close(outfile)
        next
    }
    in_mermaid {
        # Get diagram name from title if present
        if ($0 ~ /^[[:space:]]*(flowchart|sequenceDiagram|classDiagram|stateDiagram-v2|graph)/) {
            diagram_name = "'"$filename"'" "_" count
        }
        print > outfile
    }
    BEGIN {
        outfile = "/dev/null"
    }
    ' "$mdfile" 2>/dev/null
    
    # Alternative approach: use python to extract
    python3 << EOF
import re
import os
import subprocess

mdfile = "$mdfile"
filename = "$filename"
output_dir = "$OUTPUT_DIR"

with open(mdfile, 'r') as f:
    content = f.read()

# Find all mermaid blocks
pattern = r'```mermaid\n(.*?)```'
matches = re.findall(pattern, content, re.DOTALL)

for i, diagram in enumerate(matches):
    diagram_name = f"{filename}_{i+1}"
    mmd_file = os.path.join(output_dir, f"{diagram_name}.mmd")
    png_file = os.path.join(output_dir, f"{diagram_name}.png")
    
    # Write mermaid file
    with open(mmd_file, 'w') as f:
        f.write(diagram)
    
    # Convert to PNG
    try:
        subprocess.run(['mmdc', '-i', mmd_file, '-o', png_file, '-b', 'white', '-s', '2'], 
                     check=True, capture_output=True, timeout=30)
        print(f"Created: {png_file}")
    except Exception as e:
        print(f"Error creating {png_file}: {e}")
        # Try without scale
        try:
            subprocess.run(['mmdc', '-i', mmd_file, '-o', png_file, '-b', 'white'], 
                         check=True, capture_output=True, timeout=30)
            print(f"Created: {png_file}")
        except:
            pass

print(f"Processed {len(matches)} diagrams from {filename}")
EOF
done

echo "Done! Diagrams saved to $OUTPUT_DIR"
