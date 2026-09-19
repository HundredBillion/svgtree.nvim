import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
captures = root / "native-linux"
recorded = json.loads((captures / "pixels.json").read_text())

for mode in ("ordinary", "grid"):
    for name, check in recorded["colors"][mode].items():
        revision, state = {
            "sidebar": ("initial", "selected-file"),
            "divider": ("initial", "selected-file"),
            "selected": ("initial", "selected-file"),
            "hover": ("initial", "hover-file"),
            "focus_outline": ("initial", "selected-file"),
            "inactive_selection": ("final", "unfocused-selection"),
        }[name]
        x, y = check["physical_pixel"]
        image = captures / mode / revision / f"{state}.png"
        actual = subprocess.check_output(
            ["magick", image, "-format", f"%[pixel:p{{{x},{y}}}]", "info:"], text=True
        )
        assert actual == check["expected"] == check["actual"], (mode, name, actual)

files = {
    "ordinary": captures / "ordinary/initial/selected-file.png",
    "grid": captures / "grid/initial/selected-file.png",
    "reference": root / "reference/selected-file.png",
}
regions = {
    "selected_label": (132, 324, 426, 463, 180),
    "right": (16, 50, 122, 150, 100),
    "down": (16, 50, 290, 326, 100),
    "heading": (40, 230, 10, 68, 100),
}
for mode, image in files.items():
    rgb = subprocess.check_output(["magick", image, "-depth", "8", "rgb:-"])
    for name, (x0, x1, y0, y1, threshold) in regions.items():
        points = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                pixel = rgb[(y * 580 + x) * 3 : (y * 580 + x + 1) * 3]
                if min(pixel) > threshold and max(pixel) - min(pixel) < 5:
                    points.append((x, y))
        box = [min(x for x, _ in points), max(x for x, _ in points),
               min(y for _, y in points), max(y for _, y in points)]
        assert box == recorded["geometry"][mode][name], (mode, name, box)
        if mode != "reference":
            expected = recorded["geometry"]["reference"][name]
            assert max(abs(a - b) for a, b in zip(box, expected)) <= 2, (mode, name, box)

print("PASS: exact flat colors and <=1 logical pixel label/chevron/header geometry in both modes")
