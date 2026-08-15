import os
import re

replacements = {
    r'(?<!App)Colors\.white': 'AppColors.white',
    r'Color\(0x12000000\)': 'AppColors.black12',
    r'Color\(0xFFF7F5F0\)': 'AppColors.backgroundLight',
    r'Color\(0xFF26591D\)': 'AppColors.primaryGreenDark',
    r'Color\(0xFFF9FBEB\)': 'AppColors.textOnDark',
    r'Color\(0xFF111111\)': 'AppColors.textPrimary',
    r'Color\(0x99111111\)': 'AppColors.textSecondary',
    r'Color\(0xFFE0F4C8\)': 'AppColors.assistantBubble',
    r'Color\(0xFF469D60\)': 'AppColors.primaryGreenLight',
    r'Color\(0xFF3C7232\)': 'AppColors.primaryGreen',
    r'Color\(0x00100F13\)': 'AppColors.transparentBlack',
    r'Color\(0xFF080709\)': 'AppColors.deepBlack',
    r'Color\(0xFFF9D29E\)': 'AppColors.golden',
    r'Color\(0xFFEDEDED\)': 'AppColors.lightGrey',
    r'Color\(0xFFA2A2A2\)': 'AppColors.mediumGrey',
    r'Color\(0x0F000000\)': 'AppColors.black0F',
    r'(?<!App)Colors\.redAccent': 'AppColors.redAccent',
    r'(?<!App)Colors\.transparent': 'AppColors.transparent',
    r'Color\(0x66000000\)': 'AppColors.black66',
    r'Color\(0x7A000000\)': 'AppColors.black7A',
    r'Color\(0xFF08080A\)': 'AppColors.deepBlackDark',
    r'Color\(0x33000000\)': 'AppColors.black33',
    r'Color\(0x1AFFFFFF\)': 'AppColors.white1A',
    r'Color\(0xFF636363\)': 'AppColors.darkGrey',
    r'Color\(0x1A000000\)': 'AppColors.black1A',
    r'Color\(0xFF72CE50\)': 'AppColors.accentGreen',
    r'Color\(0xFFF26842\)': 'AppColors.sosOrangeLight2',
    r'Color\(0xFFF9875F\)': 'AppColors.sosGradientStart',
    r'Color\(0xFFE94E23\)': 'AppColors.sosGradientEnd',
    r'Color\(0x66E94E23\)': 'AppColors.sosGradientEnd66',
}

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart') and file != 'theme.dart':
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = content
            for pat, repl in replacements.items():
                new_content = re.sub(pat, repl, new_content)
                
            # Now remove 'const ' before AppColors
            new_content = re.sub(r'const\s+AppColors', 'AppColors', new_content)

            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Updated {filepath}')
