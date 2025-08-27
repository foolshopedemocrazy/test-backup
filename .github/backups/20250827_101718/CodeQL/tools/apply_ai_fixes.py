#!/usr/bin/env python3

import json
import os
import sys
from statistics import mean

def apply_fixes(remediation_file):
    """Apply AI-generated fixes to codebase"""
    with open(remediation_file, 'r') as f:
        fixes = json.load(f)
        
    fix_count = 0
    confidence_scores = []
    
    for fix in fixes:
        file_path = fix.get('file_path')
        if not file_path or not os.path.exists(file_path):
            print(f"Warning: File not found - {file_path}")
            continue
            
        # Read original file
        with open(file_path, 'r') as f:
            original_content = f.read()
            
        # Apply fix based on type
        if fix.get('fix_type') == 'replacement':
            start_line = fix.get('start_line', 0) - 1
            end_line = fix.get('end_line', 0)
            replacement = fix.get('replacement_code', '')
            
            lines = original_content.split('\n')
            new_content = '\n'.join(lines[:start_line] + 
                                  [replacement] + 
                                  lines[end_line:])
            
        elif fix.get('fix_type') == 'insertion':
            line = fix.get('line', 0) - 1
            code = fix.get('code', '')
            
            lines = original_content.split('\n')
            lines.insert(line, code)
            new_content = '\n'.join(lines)
            
        else:
            # For complex fixes, use the complete replacement
            new_content = fix.get('full_file_content', original_content)
            
        # Write fixed file
        with open(file_path, 'w') as f:
            f.write(new_content)
            
        fix_count += 1
        confidence_scores.append(fix.get('confidence', 0.5))
        print(f"Applied fix to {file_path}")
        
    # Generate summary
    with open("fix_summary.txt", "w") as f:
        f.write(f"Total fixes applied: {fix_count}\n")
        if confidence_scores:
            f.write(f"Average confidence: {mean(confidence_scores):.2f}\n")
    
    print(f"Successfully applied {fix_count} fixes")
    
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: apply_ai_fixes.py <remediation_file>")
        sys.exit(1)
    apply_fixes(sys.argv[1])
