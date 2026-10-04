# Environment image for CS-5187 HW-2 (fuzzing xpdf 3.02).
# Provides the AFL++ toolchain, gcov/gcovr, gnuplot, the xpdf source, and a
# ready seed. Students compile xpdf, the ASAN build, the harness, and the
# coverage build themselves.
FROM aflplusplus/aflplusplus:v4.21c

ARG STUDENT_TAG
ARG STUDENT_REPO
ARG HDR
RUN test -n "$HDR" || (echo "build via ./build.sh" && false)

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /src

COPY xpdf-3.02.tar.gz /src/
RUN tar xzf xpdf-3.02.tar.gz && rm -f xpdf-3.02.tar.gz

RUN apt-get update && \
    apt-get install -y --no-install-recommends gnuplot-nox && \
    pip3 install --no-cache-dir gcovr && \
    rm -rf /var/lib/apt/lists/*

# A ready-to-use seed, generated here so students just copy it and fuzz.
RUN python3 - <<'PY'
stream = b"BT /F1 24 Tf 72 700 Td (CS-5187 HW2) Tj ET\n"
objs = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
    b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]
out = bytearray(b"%PDF-1.4\n")
offs = []
for i, body in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
xp = len(out); n = len(objs) + 1
out += b"xref\n0 %d\n0000000000 65535 f \n" % n
for o in offs: out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (n, xp)
open("/tmp/base.pdf", "wb").write(out)
PY
RUN mkdir -p /opt/hw/seeds && \
    { printf '%s1.4\n' "$HDR"; tail -n +2 /tmp/base.pdf; } > /opt/hw/seeds/seed.pdf && \
    tail -n +2 /opt/hw/seeds/seed.pdf > /opt/hw/seeds/hseed && \
    rm -f /tmp/base.pdf

COPY tools/ /opt/hw/tools/
COPY harness/ /opt/hw/harness/
COPY dict/ /opt/hw/dict/
RUN chmod +x /opt/hw/tools/*.sh /opt/hw/harness/*.sh 2>/dev/null || true

ENV STUDENT_TAG=${STUDENT_TAG}
ENV STUDENT_REPO=${STUDENT_REPO}
WORKDIR /work
CMD ["/bin/bash"]
