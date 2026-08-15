import os

def fix_imports():
    for root, dirs, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                if 'AppColors' in content and 'theme.dart' not in content:
                    # Determine depth
                    rel_path = os.path.relpath(filepath, 'lib')
                    depth = rel_path.count(os.sep)
                    import_prefix = '../' * depth
                    import_stmt = f"import '{import_prefix}core/theme.dart';\n"
                    
                    # Insert after the last import, or at the top
                    lines = content.split('\n')
                    last_import_idx = -1
                    for i, line in enumerate(lines):
                        if line.startswith('import '):
                            last_import_idx = i
                    
                    if last_import_idx != -1:
                        lines.insert(last_import_idx + 1, import_stmt)
                    else:
                        lines.insert(0, import_stmt)
                        
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write('\n'.join(lines))
                    print(f'Added import to {filepath}')

fix_imports()
