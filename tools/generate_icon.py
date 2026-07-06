from PIL import Image, ImageDraw, ImageFont
import os
import math

PYTHON_DIR = r"C:\Users\Administrator\AppData\Local\Programs\Python\Python313"
RES_DIR = r"c:\Users\Administrator\Desktop\Solace\android\app\src\main\res"

BG_COLOR = (255, 138, 101)
HEART_COLOR = (255, 255, 255)
TEXT_COLOR = (255, 255, 255)

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

FOREGROUND_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def draw_heart(draw, cx, cy, size, color):
    points = []
    for i in range(1000):
        t = 2 * math.pi * i / 1000
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        px = cx + x * size / 32
        py = cy + y * size / 32
        points.append((px, py))
    draw.polygon(points, fill=color)


def find_font(size):
    font_paths = [
        os.path.join(PYTHON_DIR, "Lib", "site-packages", "PIL", "Fonts", "DejaVuSans-Bold.ttf"),
        os.path.join(PYTHON_DIR, "Lib", "site-packages", "tkinter", "fonts", "DejaVuSans-Bold.ttf"),
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\segoeuib.ttf",
    ]
    for fp in font_paths:
        if os.path.exists(fp):
            try:
                return ImageFont.truetype(fp, size)
            except Exception:
                continue
    return ImageFont.load_default()


def generate_legacy_icon(size, output_path):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size * 0.04
    radius = size / 2 - margin

    cx, cy = size / 2, size / 2
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=BG_COLOR)

    heart_size = size * 0.32
    heart_cy = cy - size * 0.08
    draw_heart(draw, cx, heart_cy, heart_size, HEART_COLOR)

    font_size = max(int(size * 0.13), 6)
    font = find_font(font_size)
    text = "Solace"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    text_x = (size - tw) / 2
    text_y = heart_cy + heart_size * 0.55
    draw.text((text_x, text_y), text, fill=TEXT_COLOR, font=font)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"  -> {output_path} ({size}x{size})")


def generate_foreground_icon(size, output_path):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    safe_size = size * 0.54
    offset = (size - safe_size) / 2

    heart_size = safe_size * 0.42
    heart_cx = size / 2
    heart_cy = offset + safe_size * 0.38
    draw_heart(draw, heart_cx, heart_cy, heart_size, HEART_COLOR)

    font_size = max(int(safe_size * 0.17), 6)
    font = find_font(font_size)
    text = "Solace"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    text_x = (size - tw) / 2
    text_y = heart_cy + heart_size * 0.6
    draw.text((text_x, text_y), text, fill=TEXT_COLOR, font=font)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"  -> {output_path} ({size}x{size})")


if __name__ == "__main__":
    print("=== Generating legacy icons ===")
    for folder, size in SIZES.items():
        out = os.path.join(RES_DIR, folder, "ic_launcher.png")
        generate_legacy_icon(size, out)

    print("\n=== Generating adaptive icon foreground ===")
    for folder, size in FOREGROUND_SIZES.items():
        out = os.path.join(RES_DIR, folder, "ic_launcher_foreground.png")
        generate_foreground_icon(size, out)

    print("\nDone!")
