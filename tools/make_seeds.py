# Generate structurally varied seed PDFs that carry YOUR header line (Task 2).
#   python3 tools/make_seeds.py /opt/hw/seeds/seed.pdf work-out/seeds
import zlib, base64, binascii, os, sys
hdr = open(sys.argv[1], 'rb').readline()          # your personal header line
out = sys.argv[2]; os.makedirs(out, exist_ok=True)
TXT = b"BT /F1 12 Tf 72 700 Td (Hello fuzz) Tj ET\n"
RICH = (b"q 1 0 0 1 10 10 cm 0.5 g 0 0 100 50 re f Q\n"
        b"BT /F1 10 Tf 14 TL 72 650 Td (line1) Tj T* [(A) -120 (B)] TJ (q) ' 1 0 0 1 72 600 Tm (x) Tj ET\n"
        b"BI /W 2 /H 2 /BPC 8 /CS /G ID \x00\xff\xff\x00 EI\n")

def stream(body, d=b""):
    return b"<< /Length %d %s>>\nstream\n" % (len(body), d) + body + b"\nendstream"

def objs(contents, page_extra=b"", cat_extra=b"", extra=()):
    return [b"<< /Type /Catalog /Pages 2 0 R " + cat_extra + b">>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R " + page_extra + b">>",
            contents,
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"] + list(extra)

def body(ol):
    d = bytearray(hdr); offs = []
    for i, o in enumerate(ol, 1):
        offs.append(len(d)); d += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    return d, offs

def build(ol, info=False):
    d, offs = body(ol); x = len(d); n = len(ol) + 1
    d += b"xref\n0 %d\n0000000000 65535 f \n" % n
    for o in offs: d += b"%010d 00000 n \n" % o
    d += b"trailer\n<< /Size %d /Root 1 0 R %s>>\nstartxref\n%d\n%%%%EOF\n" % (n, b"/Info 6 0 R " if info else b"", x)
    return bytes(d), x

def rle(b):
    r = b""
    for i in range(0, len(b), 100): c = b[i:i+100]; r += bytes([len(c) - 1]) + c
    return r + b"\x80"

def tiff_rows(b, cols=4):
    b += b" " * (-len(b) % cols); o = bytearray()
    for i in range(0, len(b), cols):
        r = b[i:i+cols]; o += bytes([r[0]] + [(r[j] - r[j-1]) & 255 for j in range(1, cols)])
    return bytes(o)

def png_rows(b, cols=8):
    b += b" " * (-len(b) % cols)
    return b"".join(b"\x00" + b[i:i+cols] for i in range(0, len(b), cols))

S = {}
S["plain"]   = build(objs(stream(TXT)))[0]
S["rich"]    = build(objs(stream(RICH)))[0]
S["flate"]   = build(objs(stream(zlib.compress(TXT), b"/Filter /FlateDecode ")))[0]
S["ahex"]    = build(objs(stream(binascii.hexlify(TXT) + b">", b"/Filter /ASCIIHexDecode ")))[0]
S["a85"]     = build(objs(stream(base64.a85encode(TXT) + b"~>", b"/Filter /ASCII85Decode ")))[0]
S["rle"]     = build(objs(stream(rle(RICH), b"/Filter /RunLengthDecode ")))[0]
S["chain"]   = build(objs(stream(binascii.hexlify(zlib.compress(RICH)) + b">", b"/Filter [/ASCIIHexDecode /FlateDecode] ")))[0]
S["predict"] = build(objs(stream(zlib.compress(png_rows(TXT)), b"/Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 8 >> ")))[0]
S["tiffpred"] = build(objs(stream(zlib.compress(tiff_rows(TXT)), b"/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 1 /BitsPerComponent 8 /Columns 4 >> ")))[0]
S["info_outline_annot"] = build(objs(stream(RICH),
    page_extra=b"/Annots [<< /Type /Annot /Subtype /Link /Rect [0 0 50 50] /Border [0 0 1] /Dest [3 0 R /XYZ 0 792 0] >>] ",
    cat_extra=b"/Outlines 7 0 R /PageMode /UseOutlines ",
    extra=[b"<< /Title (seed) /Author (me) /Producer (x) >>",
           b"<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 1 >>",
           b"<< /Title (Ch1) /Parent 7 0 R /Dest [3 0 R /Fit] >>"]), info=True)[0]
# indirect /Length
S["indlen"] = build(objs(b"<< /Length 6 0 R >>\nstream\n" + TXT + b"\nendstream", extra=[b"%d" % len(TXT)]))[0]
# broken startxref -> xref reconstruction path
d, x = build(objs(stream(TXT))); S["brokenxref"] = d.replace(b"startxref\n%d" % x, b"startxref\n%d" % (x + 7))
# incremental update with /Prev
d, x = build(objs(stream(TXT)))
off = len(d); upd = b"4 0 obj\n" + stream(RICH) + b"\nendobj\n"; x2 = off + len(upd)
S["incremental"] = d + upd + b"xref\n0 1\n0000000000 65535 f \n4 1\n%010d 00000 n \ntrailer\n<< /Size 6 /Root 1 0 R /Prev %d >>\nstartxref\n%d\n%%%%EOF\n" % (off, x, x2)
# cross-reference stream
ol = objs(stream(zlib.compress(TXT), b"/Filter /FlateDecode "))
d, offs = body(ol); n = len(ol) + 1; xo = len(d)
rows = b"\x00\x00\x00\x00\x00\xff" + b"".join(b"\x01" + o.to_bytes(4, "big") + b"\x00" for o in offs + [xo])
xs = zlib.compress(rows)
d += b"%d 0 obj\n<< /Type /XRef /Size %d /W [1 4 1] /Root 1 0 R /Filter /FlateDecode /Length %d >>\nstream\n" % (n, n + 1, len(xs)) + xs + b"\nendstream\nendobj\nstartxref\n%d\n%%%%EOF\n" % xo
S["xrefstream"] = bytes(d)
# two pages, nested arrays/dicts, page tree with inheritance
two = [b"<< /Type /Catalog /Pages 2 0 R >>",
       b"<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> >>",
       b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R /Rotate 90 >>", stream(TXT),
       b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
       b"<< /Type /Page /Parent 2 0 R /Contents [4 0 R 7 0 R] /Extra [1 2.5 -3 true false null (s) <414243> /N [[1] << /K [<< >>] >>]] >>",
       stream(RICH)]
S["twopage_nested"] = build(two)[0]

for k, v in S.items():
    open(os.path.join(out, k + ".pdf"), "wb").write(v)
print("wrote %d seeds to %s" % (len(S), out))
