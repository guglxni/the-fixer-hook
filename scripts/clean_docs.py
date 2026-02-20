#!/usr/bin/env python3
"""Clean emojis from markdown files and update mermaid diagrams to professional style."""

import os
import re
import glob

# Emoji pattern (comprehensive)
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F680-\U0001F6FF"  # transport & map symbols
    "\U0001F1E0-\U0001F1FF"  # flags (iOS)
    "\U00002702-\U000027B0"
    "\U000024C2-\U0001F251"
    "\U0001f926-\U0001f937"
    "\U00010000-\U0010ffff"
    "\u2640-\u2642"
    "\u2600-\u2B55"
    "\u200d"
    "\u23cf"
    "\u23e9"
    "\u231a"
    "\ufe0f"
    "\u3030"
    "]+"
)

# Professional mermaid theme config
PROFESSIONAL_THEME = """
%%{init: {'theme': 'neutral', 'themeVariables': { 'primaryColor': '#2563eb', 'primaryTextColor': '#1e293b', 'primaryBorderColor': '#3b82f6', 'lineColor': '#64748b', 'secondaryColor': '#f1f5f9', 'tertiaryColor': '#e2e8f0'}}}%%
"""

def remove_emojis(text):
    """Remove all emojis from text."""
    return EMOJI_PATTERN.sub('', text)

def update_mermaid_theme(mermaid_code):
    """Add professional theme to mermaid diagrams if not present."""
    lines = mermaid_code.strip().split('\n')
    
    # Check if theme is already set
    has_theme = any('%%{' in line or 'theme:' in line for line in lines[:5])
    
    if not has_theme:
        # Add theme after any comments
        new_lines = []
        for line in lines:
            if line.strip().startswith('%%'):
                new_lines.append(line)
            else:
                new_lines.append(PROFESSIONAL_THEME.strip())
                new_lines.append(line)
                break
        # If no comments, add theme at beginning
        if not new_lines:
            new_lines = [PROFESSIONAL_THEME.strip()] + lines
        
        # Ensure remaining lines are there
        for line in lines[len(new_lines):]:
            if line.strip():
                new_lines.append(line)
        
        return '\n'.join(new_lines)
    
    return mermaid_code

def process_markdown_file(filepath):
    """Process a single markdown file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # Remove emojis
    content = remove_emojis(text=content)
    
    # Update mermaid blocks
    def replace_mermaid(match):
        mermaid_code = match.group(1)
        mermaid_code = remove_emojis(mermaid_code)
        mermaid_code = update_mermaid_theme(mermaid_code)
        return f'```mermaid\n{mermaid_code}\n```'
    
    # Find and replace mermaid blocks
    pattern = r'```mermaid\n(.*?)```'
    content = re.sub(pattern, replace_mermaid, content, flags=re.DOTALL)
    
    # Write back if changed
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Cleaned: {filepath}")
        return True
    return False

def main():
    """Main function."""
    docs_dir = "docs"
    
    # Process all markdown files
    md_files = glob.glob(f"{docs_dir}/*.md")
    
    for filepath in md_files:
        process_markdown_file(filepath)
    
    print(f"Processed {len(md_files)} markdown files")

if __name__ == "__main__":
    main()
