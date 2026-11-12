import os
import math
from PIL import Image, ImageDraw, ImageFilter

def extract_emblem(icon_path):
    img = Image.open(icon_path).convert('RGB')
    w, h = img.size
    cx, cy = w / 2.0, h / 2.0

    rgba = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    bg_r, bg_g, bg_b = 36, 41, 61

    for y in range(h):
        for x in range(w):
            dist = math.hypot(x - cx, y - cy)
            if dist > 680:
                continue
            r, g, b = img.getpixel((x, y))
            diff = math.sqrt((r - bg_r)**2 + (g - bg_g)**2 + (b - bg_b)**2)
            if diff < 22:
                alpha = 0
            elif diff > 50:
                alpha = 255
            else:
                alpha = int((diff - 22) / 28.0 * 255)

            if alpha > 0:
                rgba.putpixel((x, y), (r, g, b, alpha))

    bbox = rgba.getbbox()
    cropped = rgba.crop(bbox)

    # Square 1024x1024 canvas with 12% padding
    canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    scale = 800.0 / max(cropped.size)
    new_w = int(cropped.width * scale)
    new_h = int(cropped.height * scale)
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((1024 - new_w) // 2, (1024 - new_h) // 2), resized)
    return canvas

def tint_emblem(emblem_img, grad_start, grad_end):
    w, h = emblem_img.size
    tinted = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for y in range(h):
        ratio = y / float(h)
        # linear interpolate color
        r = int(grad_start[0] * (1 - ratio) + grad_end[0] * ratio)
        g = int(grad_start[1] * (1 - ratio) + grad_end[1] * ratio)
        b = int(grad_start[2] * (1 - ratio) + grad_end[2] * ratio)
        for x in range(w):
            _, _, _, a = emblem_img.getpixel((x, y))
            if a > 0:
                tinted.putpixel((x, y), (r, g, b, a))
    return tinted

def create_squircle_mask(size, radius):
    mask = Image.new('L', (size * 4, size * 4), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size * 4, size * 4], radius=radius * 4, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)

def create_styled_icon(emblem_img, bg_top, bg_bottom, emblem_tint_start=None, emblem_tint_end=None, size=1024):
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    # Background gradient
    bg = Image.new('RGBA', (size, size), (0, 0, 0, 255))
    for y in range(size):
        r = y / float(size)
        cr = int(bg_top[0] * (1 - r) + bg_bottom[0] * r)
        cg = int(bg_top[1] * (1 - r) + bg_bottom[1] * r)
        cb = int(bg_top[2] * (1 - r) + bg_bottom[2] * r)
        for x in range(size):
            bg.putpixel((x, y), (cr, cg, cb, 255))

    # Apply squircle mask (22% radius for Apple/Android squircle)
    mask = create_squircle_mask(size, int(size * 0.22))
    icon.paste(bg, (0, 0), mask)

    # Tint or scale emblem
    if emblem_tint_start and emblem_tint_end:
        active_emblem = tint_emblem(emblem_img, emblem_tint_start, emblem_tint_end)
    else:
        active_emblem = emblem_img

    # Emblem scale ~62%
    emb_size = int(size * 0.62)
    scaled_emb = active_emblem.resize((emb_size, emb_size), Image.Resampling.LANCZOS)
    offset = (size - emb_size) // 2
    icon.paste(scaled_emb, (offset, offset), scaled_emb)

    # Subtle inner border stroke for glass/card finish
    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle([2, 2, size - 3, size - 3], radius=int(size * 0.22), outline=(255, 255, 255, 35), width=int(size * 0.008))
    return icon

def main():
    print("1. Extracting pure emblem from icon.jpg...")
    emblem = extract_emblem('icon.jpg')
    os.makedirs('assets/images/icons', exist_ok=True)
    emblem.save('assets/images/app_logo.png')
    print("   -> Saved assets/images/app_logo.png (1024x1024)")

    # 4 Styles
    styles = {
        'default': {
            'bg_top': (26, 32, 54),
            'bg_bottom': (12, 15, 28),
            'tint_start': (140, 215, 180),
            'tint_end': (145, 175, 240)
        },
        'neon': {
            'bg_top': (34, 16, 58),
            'bg_bottom': (12, 6, 26),
            'tint_start': (60, 245, 215),
            'tint_end': (195, 120, 255)
        },
        'stealth': {
            'bg_top': (28, 28, 30),
            'bg_bottom': (12, 12, 14),
            'tint_start': (255, 215, 120),
            'tint_end': (240, 165, 45)
        },
        'silver': {
            'bg_top': (248, 250, 254),
            'bg_bottom': (218, 225, 236),
            'tint_start': (24, 42, 75),
            'tint_end': (38, 70, 125)
        }
    }

    generated_icons = {}
    for name, cfg in styles.items():
        print(f"2. Generating style '{name}'...")
        icon_img = create_styled_icon(
            emblem,
            cfg['bg_top'],
            cfg['bg_bottom'],
            cfg['tint_start'],
            cfg['tint_end'],
            size=1024
        )
        generated_icons[name] = icon_img
        # Save 512x512 preview asset
        preview = icon_img.resize((512, 512), Image.Resampling.LANCZOS)
        preview.save(f'assets/images/icons/icon_{name}.png')

    # Android mipmaps
    android_res = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, dim in android_res.items():
        dir_path = os.path.join('android/app/src/main/res', folder)
        os.makedirs(dir_path, exist_ok=True)
        # default launcher
        generated_icons['default'].resize((dim, dim), Image.Resampling.LANCZOS).save(os.path.join(dir_path, 'ic_launcher.png'))
        # alternate icons
        for name in ['neon', 'stealth', 'silver']:
            generated_icons[name].resize((dim, dim), Image.Resampling.LANCZOS).save(os.path.join(dir_path, f'ic_launcher_{name}.png'))
    print("   -> Android launcher mipmaps updated!")

    # Web Icons
    web_dir = 'web'
    icons_dir = os.path.join(web_dir, 'icons')
    os.makedirs(icons_dir, exist_ok=True)
    generated_icons['default'].resize((32, 32), Image.Resampling.LANCZOS).save(os.path.join(web_dir, 'favicon.png'))
    generated_icons['default'].resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-192.png'))
    generated_icons['default'].resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-512.png'))
    generated_icons['default'].resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-maskable-192.png'))
    generated_icons['default'].resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, 'Icon-maskable-512.png'))
    # Save alternates for web dynamic favicon
    for name in ['neon', 'stealth', 'silver']:
        generated_icons[name].resize((32, 32), Image.Resampling.LANCZOS).save(os.path.join(web_dir, f'favicon_{name}.png'))
    print("   -> Web icons & favicons updated!")

    # macOS icons
    mac_dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(mac_dir):
        sizes = [16, 32, 64, 128, 256, 512, 1024]
        for s in sizes:
            generated_icons['default'].resize((s, s), Image.Resampling.LANCZOS).save(os.path.join(mac_dir, f'app_icon_{s}.png'))
        print("   -> macOS app icons updated!")

    # iOS icons
    ios_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(ios_dir):
        generated_icons['default'].resize((1024, 1024), Image.Resampling.LANCZOS).save(os.path.join(ios_dir, 'Icon-App-1024x1024@1x.png'))
        # Other standard sizes
        ios_sizes = {
            'Icon-App-20x20@1x.png': 20,
            'Icon-App-20x20@2x.png': 40,
            'Icon-App-20x20@3x.png': 60,
            'Icon-App-29x29@1x.png': 29,
            'Icon-App-29x29@2x.png': 58,
            'Icon-App-29x29@3x.png': 87,
            'Icon-App-40x40@1x.png': 40,
            'Icon-App-40x40@2x.png': 80,
            'Icon-App-40x40@3x.png': 120,
            'Icon-App-60x60@2x.png': 120,
            'Icon-App-60x60@3x.png': 180,
            'Icon-App-76x76@1x.png': 76,
            'Icon-App-76x76@2x.png': 152,
            'Icon-App-83.5x83.5@2x.png': 167,
        }
        for fname, dim in ios_sizes.items():
            generated_icons['default'].resize((dim, dim), Image.Resampling.LANCZOS).save(os.path.join(ios_dir, fname))
        print("   -> iOS app icons updated!")

    # Windows ICO
    win_ico = 'windows/runner/resources/app_icon.ico'
    if os.path.exists(os.path.dirname(win_ico)):
        generated_icons['default'].save(win_ico, format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])
        print("   -> Windows app_icon.ico updated!")

    print("All icons successfully generated!")

if __name__ == '__main__':
    main()
