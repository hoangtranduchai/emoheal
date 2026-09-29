import os
import io
import re
import shutil
import base64
from PIL import Image, ImageDraw, ImageFont

COLOR_BG_HEX = "#F7F5F0"
COLOR_BG_RGB = (247, 245, 240, 255)
COLOR_PRIMARY_DARK = (38, 89, 29, 255)
COLOR_PRIMARY_GREEN = (60, 114, 50, 255)
COLOR_TEXT_PRIMARY = (17, 17, 17, 255)

SVG_SOURCE = r"D:\Downloads\Logo_EmoHeal.svg"
PROJECT_ROOT = r"e:\EmoHeal"

# Android Adaptive Icon Canvas is 108dp. Visible mask is 72dp.
# To make the logo occupy ~68% of the visible mask with elegant padding,
# the logo must be 46% of the total 108dp canvas (46% * 108dp = ~50dp logo in 72dp mask).
ADAPTIVE_FG_RATIO = 0.46
LEGACY_MIPMAP_RATIO = 0.65
IOS_RATIO = 0.70

def extract_master_rgba(svg_path: str) -> Image.Image:
    print(f"[*] Reading master SVG from: {svg_path}")
    with open(svg_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    b64_matches = re.findall(r"base64,([A-Za-z0-9+/=]+)", content)
    if len(b64_matches) < 2:
        raise ValueError(f"Expected at least 2 base64 streams in SVG, found {len(b64_matches)}")

    mask_raw = base64.b64decode(b64_matches[0])
    color_raw = base64.b64decode(b64_matches[1])

    mask_img = Image.open(io.BytesIO(mask_raw)).convert("L")
    color_img = Image.open(io.BytesIO(color_raw)).convert("RGB")

    rgba = Image.merge("RGBA", (*color_img.split(), mask_img))
    
    bbox = rgba.getbbox()
    print(f"[*] Raw RGBA size: {rgba.size}, Bounding Box: {bbox}")
    cropped = rgba.crop(bbox)
    
    max_dim = max(cropped.width, cropped.height)
    square_canvas = Image.new("RGBA", (max_dim, max_dim), (0, 0, 0, 0))
    offset = ((max_dim - cropped.width) // 2, (max_dim - cropped.height) // 2)
    square_canvas.paste(cropped, offset, cropped)
    
    print(f"[*] Master centered square RGBA size: {square_canvas.size}")
    return square_canvas

def create_padded_icon(base_img: Image.Image, canvas_size: int, scale_ratio: float, bg_color=None) -> Image.Image:
    if bg_color:
        canvas = Image.new("RGBA", (canvas_size, canvas_size), bg_color)
    else:
        canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    
    target_dim = int(round(canvas_size * scale_ratio))
    resized_logo = base_img.resize((target_dim, target_dim), Image.Resampling.LANCZOS)
    
    offset = ((canvas_size - target_dim) // 2, (canvas_size - target_dim) // 2)
    canvas.paste(resized_logo, offset, resized_logo)
    return canvas

def create_monochrome_notification_icon(base_img: Image.Image, canvas_size: int, scale_ratio: float = 0.75) -> Image.Image:
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    target_dim = int(round(canvas_size * scale_ratio))
    resized_logo = base_img.resize((target_dim, target_dim), Image.Resampling.LANCZOS)
    
    alpha = resized_logo.split()[3]
    white_img = Image.new("RGBA", (target_dim, target_dim), (255, 255, 255, 255))
    white_img.putalpha(alpha)
    
    offset = ((canvas_size - target_dim) // 2, (canvas_size - target_dim) // 2)
    canvas.paste(white_img, offset, white_img)
    return canvas

def generate_all():
    print("===============================================================")
    print("       EMOHEAL MASTER ICON AND ASSET GENERATION PIPELINE       ")
    print(f"       Adaptive Foreground Canvas Ratio: {ADAPTIVE_FG_RATIO * 100:.1f}%")
    print(f"       Visible Mask Logo Coverage: {(ADAPTIVE_FG_RATIO * 108 / 72) * 100:.1f}% (Generous Padding)")
    print("===============================================================")

    master_rgba = extract_master_rgba(SVG_SOURCE)

    dirs_to_ensure = [
        os.path.join(PROJECT_ROOT, "assets", "icons"),
        os.path.join(PROJECT_ROOT, "assets", "images"),
        os.path.join(PROJECT_ROOT, "assets", "store"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "drawable-mdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "drawable-hdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "drawable-xhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "drawable-xxhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "drawable-xxxhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-mdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-hdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-xhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-xxhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-xxxhdpi"),
        os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-anydpi-v26"),
        os.path.join(PROJECT_ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"),
        os.path.join(PROJECT_ROOT, "web", "icons"),
        os.path.join(PROJECT_ROOT, "windows", "runner", "resources"),
    ]
    for d in dirs_to_ensure:
        os.makedirs(d, exist_ok=True)

    # 1. In-App Flutter UI Assets
    print("\n[+] Generating In-App Flutter UI Assets...")
    dst_svg = os.path.join(PROJECT_ROOT, "assets", "icons", "app_icon.svg")
    shutil.copyfile(SVG_SOURCE, dst_svg)
    print(f"  -> Saved {dst_svg}")

    # App icon on brand background with generous padding
    app_icon_padded = create_padded_icon(master_rgba, 1024, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    dst_app_icon_png = os.path.join(PROJECT_ROOT, "assets", "icons", "app_icon.png")
    app_icon_padded.save(dst_app_icon_png, "PNG")
    print(f"  -> Saved {dst_app_icon_png}")

    # Transparent master 1024x1024 for in-app UI widgets
    master_1024_transparent = create_padded_icon(master_rgba, 1024, 1.0)
    dst_images_app_icon = os.path.join(PROJECT_ROOT, "assets", "images", "app_icon.png")
    master_1024_transparent.save(dst_images_app_icon, "PNG")
    print(f"  -> Saved {dst_images_app_icon}")

    # Padded foreground 432x432 (46% ratio on 108dp canvas -> ~69% visible in 72dp squircle)
    app_icon_fg_432 = create_padded_icon(master_rgba, 432, ADAPTIVE_FG_RATIO)
    dst_app_icon_fg = os.path.join(PROJECT_ROOT, "assets", "icons", "app_icon_foreground.png")
    app_icon_fg_432.save(dst_app_icon_fg, "PNG")
    print(f"  -> Saved {dst_app_icon_fg}")

    # 2. Android Native Assets
    print("\n[+] Generating Android Native Assets with Elegant Safe-Zone Padding...")
    adaptive_fg_sizes = {
        "drawable-mdpi": 108,
        "drawable-hdpi": 162,
        "drawable-xhdpi": 216,
        "drawable-xxhdpi": 324,
        "drawable-xxxhdpi": 432,
    }
    for folder, size in adaptive_fg_sizes.items():
        fg_img = create_padded_icon(master_rgba, size, ADAPTIVE_FG_RATIO)
        path = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", folder, "ic_launcher_foreground.png")
        fg_img.save(path, "PNG")
        print(f"  -> Saved {path} ({size}x{size})")

    # Legacy Mipmaps - BOTH square and round use LEGACY_MIPMAP_RATIO (65%) on #F7F5F0 background!
    legacy_mipmap_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in legacy_mipmap_sizes.items():
        legacy_icon = create_padded_icon(master_rgba, size, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
        path = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", folder, "ic_launcher.png")
        legacy_icon.save(path, "PNG")
        print(f"  -> Saved {path} ({size}x{size})")

        round_icon = create_padded_icon(master_rgba, size, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
        round_path = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", folder, "ic_launcher_round.png")
        round_icon.save(round_path, "PNG")
        print(f"  -> Saved {round_path} ({size}x{size})")

    # Ensure both ic_launcher.xml and ic_launcher_round.xml exist in mipmap-anydpi-v26
    anydpi_dir = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "mipmap-anydpi-v26")
    adaptive_xml_content = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
"""
    with open(os.path.join(anydpi_dir, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(adaptive_xml_content)
    with open(os.path.join(anydpi_dir, "ic_launcher_round.xml"), "w", encoding="utf-8") as f:
        f.write(adaptive_xml_content)
    print("  -> Updated mipmap-anydpi-v26/ic_launcher.xml & ic_launcher_round.xml")

    notif_sizes = {
        "drawable-mdpi": 24,
        "drawable-hdpi": 36,
        "drawable-xhdpi": 48,
        "drawable-xxhdpi": 72,
        "drawable-xxxhdpi": 96,
    }
    for folder, size in notif_sizes.items():
        notif_img = create_monochrome_notification_icon(master_rgba, size, 0.70)
        path = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", folder, "ic_notification.png")
        notif_img.save(path, "PNG")
        print(f"  -> Saved {path} ({size}x{size})")

    colors_xml_path = os.path.join(PROJECT_ROOT, "android", "app", "src", "main", "res", "values", "colors.xml")
    colors_xml_content = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{COLOR_BG_HEX}</color>
    <color name="primary_green_dark">#26591D</color>
    <color name="primary_green">#3C7232</color>
</resources>
"""
    with open(colors_xml_path, "w", encoding="utf-8") as f:
        f.write(colors_xml_content)
    print(f"  -> Updated {colors_xml_path}")

    # 3. iOS Native Assets (70% Safe Zone on #F7F5F0 background)
    print("\n[+] Generating iOS AppIcon Set...")
    ios_icons = [
        ("Icon-App-1024x1024@1x.png", 1024),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-72x72@1x.png", 72),
        ("Icon-App-72x72@2x.png", 144),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-57x57@1x.png", 57),
        ("Icon-App-57x57@2x.png", 114),
        ("Icon-App-50x50@1x.png", 50),
        ("Icon-App-50x50@2x.png", 100),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
    ]
    ios_base_dir = os.path.join(PROJECT_ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for filename, size in ios_icons:
        icon_img = create_padded_icon(master_rgba, size, IOS_RATIO, bg_color=COLOR_BG_RGB)
        rgb_icon = Image.new("RGB", (size, size), (247, 245, 240))
        rgb_icon.paste(icon_img, (0, 0), icon_img)
        path = os.path.join(ios_base_dir, filename)
        rgb_icon.save(path, "PNG")
        print(f"  -> Saved {path} ({size}x{size})")

    # 4. Web & PWA Assets
    print("\n[+] Generating Web and PWA Assets...")
    fav_png = create_padded_icon(master_rgba, 64, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    fav_png_path = os.path.join(PROJECT_ROOT, "web", "favicon.png")
    fav_png.save(fav_png_path, "PNG")
    print(f"  -> Saved {fav_png_path}")

    fav_ico_16 = create_padded_icon(master_rgba, 16, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    fav_ico_32 = create_padded_icon(master_rgba, 32, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    fav_ico_48 = create_padded_icon(master_rgba, 48, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    fav_ico_path = os.path.join(PROJECT_ROOT, "web", "favicon.ico")
    fav_ico_48.save(fav_ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    print(f"  -> Saved {fav_ico_path}")

    pwa_192 = create_padded_icon(master_rgba, 192, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    pwa_192_path = os.path.join(PROJECT_ROOT, "web", "icons", "Icon-192.png")
    pwa_192.save(pwa_192_path, "PNG")
    print(f"  -> Saved {pwa_192_path}")

    pwa_512 = create_padded_icon(master_rgba, 512, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    pwa_512_path = os.path.join(PROJECT_ROOT, "web", "icons", "Icon-512.png")
    pwa_512.save(pwa_512_path, "PNG")
    print(f"  -> Saved {pwa_512_path}")

    pwa_mask_192 = create_padded_icon(master_rgba, 192, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    pwa_mask_192_path = os.path.join(PROJECT_ROOT, "web", "icons", "Icon-maskable-192.png")
    pwa_mask_192.save(pwa_mask_192_path, "PNG")
    print(f"  -> Saved {pwa_mask_192_path}")

    pwa_mask_512 = create_padded_icon(master_rgba, 512, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    pwa_mask_512_path = os.path.join(PROJECT_ROOT, "web", "icons", "Icon-maskable-512.png")
    pwa_mask_512.save(pwa_mask_512_path, "PNG")
    print(f"  -> Saved {pwa_mask_512_path}")

    # 5. Windows Desktop Icon
    print("\n[+] Generating Windows Desktop Icon...")
    win_ico_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    win_master = create_padded_icon(master_rgba, 256, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    win_ico_path = os.path.join(PROJECT_ROOT, "windows", "runner", "resources", "app_icon.ico")
    win_master.save(win_ico_path, format="ICO", sizes=win_ico_sizes)
    print(f"  -> Saved {win_ico_path}")

    # 6. Store & Marketing Assets
    print("\n[+] Generating Store Marketing Assets...")
    play_512 = create_padded_icon(master_rgba, 512, LEGACY_MIPMAP_RATIO, bg_color=COLOR_BG_RGB)
    play_512_path = os.path.join(PROJECT_ROOT, "assets", "store", "play_store_512.png")
    play_512.save(play_512_path, "PNG")
    print(f"  -> Saved {play_512_path}")

    app_store_1024 = create_padded_icon(master_rgba, 1024, IOS_RATIO, bg_color=COLOR_BG_RGB)
    rgb_app_store = Image.new("RGB", (1024, 1024), (247, 245, 240))
    rgb_app_store.paste(app_store_1024, (0, 0), app_store_1024)
    app_store_path = os.path.join(PROJECT_ROOT, "assets", "store", "app_store_1024.png")
    rgb_app_store.save(app_store_path, "PNG")
    print(f"  -> Saved {app_store_path}")

    feature_banner = Image.new("RGBA", (1024, 500), COLOR_BG_RGB)
    banner_logo_dim = 260
    banner_logo = master_rgba.resize((banner_logo_dim, banner_logo_dim), Image.Resampling.LANCZOS)
    logo_x = 100
    logo_y = (500 - banner_logo_dim) // 2
    feature_banner.paste(banner_logo, (logo_x, logo_y), banner_logo)

    draw = ImageDraw.Draw(feature_banner)
    font_bold_path = os.path.join(PROJECT_ROOT, "assets", "fonts", "Roboto-Bold.ttf")
    font_reg_path = os.path.join(PROJECT_ROOT, "assets", "fonts", "Roboto-Regular.ttf")
    
    try:
        font_title = ImageFont.truetype(font_bold_path, 52)
        font_subtitle = ImageFont.truetype(font_reg_path, 26)
        font_tagline = ImageFont.truetype(font_reg_path, 20)
    except Exception as e:
        print(f"  [!] Font load warning: {e}")
        font_title = ImageFont.load_default()
        font_subtitle = font_title
        font_tagline = font_title

    text_x = logo_x + banner_logo_dim + 45
    draw.text((text_x, 155), "EmoHeal", font=font_title, fill=COLOR_PRIMARY_DARK)
    draw.text((text_x, 230), "Vòng tay thấu cảm & Lắng nghe", font=font_subtitle, fill=COLOR_PRIMARY_GREEN)
    draw.text((text_x, 275), "Hỗ trợ Tâm lý & Đồng hành Cựu chiến binh", font=font_tagline, fill=(100, 100, 100, 255))

    feature_banner_path = os.path.join(PROJECT_ROOT, "assets", "store", "feature_graphic_1024x500.png")
    rgb_feature_banner = Image.new("RGB", (1024, 500), (247, 245, 240))
    rgb_feature_banner.paste(feature_banner, (0, 0), feature_banner)
    rgb_feature_banner.save(feature_banner_path, "PNG")
    print(f"  -> Saved {feature_banner_path}")

    og_banner = Image.new("RGBA", (1200, 630), COLOR_BG_RGB)
    og_logo_dim = 320
    og_logo = master_rgba.resize((og_logo_dim, og_logo_dim), Image.Resampling.LANCZOS)
    og_x = 120
    og_y = (630 - og_logo_dim) // 2
    og_banner.paste(og_logo, (og_x, og_y), og_logo)

    draw_og = ImageDraw.Draw(og_banner)
    try:
        font_og_title = ImageFont.truetype(font_bold_path, 64)
        font_og_sub = ImageFont.truetype(font_reg_path, 32)
        font_og_tag = ImageFont.truetype(font_reg_path, 24)
    except Exception:
        font_og_title = ImageFont.load_default()
        font_og_sub = font_og_title
        font_og_tag = font_og_title

    og_text_x = og_x + og_logo_dim + 55
    draw_og.text((og_text_x, 200), "EmoHeal", font=font_og_title, fill=COLOR_PRIMARY_DARK)
    draw_og.text((og_text_x, 285), "Vòng tay thấu cảm", font=font_og_sub, fill=COLOR_PRIMARY_GREEN)
    draw_og.text((og_text_x, 340), "Chăm sóc & Lắng nghe Tâm lý Người cao tuổi", font=font_og_tag, fill=(100, 100, 100, 255))

    og_banner_path = os.path.join(PROJECT_ROOT, "assets", "store", "opengraph_banner_1200x630.png")
    rgb_og_banner = Image.new("RGB", (1200, 630), (247, 245, 240))
    rgb_og_banner.paste(og_banner, (0, 0), og_banner)
    rgb_og_banner.save(og_banner_path, "PNG")
    print(f"  -> Saved {og_banner_path}")

    shutil.copyfile(og_banner_path, os.path.join(PROJECT_ROOT, "web", "og_image.png"))

    print("\n===============================================================")
    print("      SUCCESS: ALL ASSETS GENERATED PIXEL-PERFECT!            ")
    print("===============================================================")

if __name__ == "__main__":
    generate_all()
