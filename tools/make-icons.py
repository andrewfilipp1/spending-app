"""Renders the app icons as PNG with only the standard library (no Pillow)."""
import struct, sys, zlib, os

def png(path, size, ss=3):
    W = size * ss
    def bg(x, y):  # diagonal gradient #10b981 -> #0e7490
        t = (x + y) / (2 * W)
        a, b = (0x10, 0xB9, 0x81), (0x0E, 0x74, 0x90)
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
    # three rounded bars (a growing chart) in white
    bars = [(0.22, 0.56), (0.42, 0.40), (0.62, 0.24)]  # (left, top) in unit coords
    bw, bottom, r = 0.16, 0.78, 0.05
    def inside(u, v):
        for left, top in bars:
            if left <= u <= left + bw and top <= v <= bottom:
                cx = min(max(u, left + r), left + bw - r)
                cy = min(max(v, top + r), bottom - r)
                if (u - cx) ** 2 + (v - cy) ** 2 <= r * r:
                    return True
        return False
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            acc = [0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    px, py = x * ss + sx + 0.5, y * ss + sy + 0.5
                    c = (255, 255, 255) if inside(px / W, py / W) else bg(px, py)
                    for i in range(3):
                        acc[i] += c[i]
            rows += bytes(int(v / (ss * ss) + 0.5) for v in acc)
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(data)

# usage: make-icons.py <dir>            → web icons
#        make-icons.py <file.png> <size> → a single icon (e.g. the 1024px iOS icon)
if len(sys.argv) == 3:
    png(sys.argv[1], int(sys.argv[2]), ss=2)
else:
    out = sys.argv[1]
    for name, size in [('icon-192.png', 192), ('apple-touch-icon.png', 180), ('icon-512.png', 512)]:
        png(os.path.join(out, name), size)
