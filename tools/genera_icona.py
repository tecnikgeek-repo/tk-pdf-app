"""Icone di tk-pdf mobile, disegnate come quelle dell'app desktop.

Produce:
  assets/icona.png          1024x1024, icona intera (iPhone e Android vecchio)
  assets/icona-adattiva.png 1024x1024, solo il foglio su trasparente (Android adattiva, fondo navy)

Uso (serve PySide6, si prende dall'ambiente dell'app desktop):
  set PYTHONPATH=C:\\Users\\TecnikGeek\\tk-pdf\\.venv\\Lib\\site-packages
  python tools/genera_icona.py
"""
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
# senza questa riga, in modalità senza schermo mancano i caratteri e «PDF» esce a quadratini
os.environ.setdefault("QT_QPA_FONTDIR", os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts"))

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QImage, QLinearGradient, QPainter, QPainterPath
from PySide6.QtWidgets import QApplication

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(RADICE, "assets")


def disegna(size, con_fondo=True, margine=1.0):
    """Stesso disegno dell'icona desktop (tkpdf/icon.py). margine < 1 rimpicciolisce il foglio."""
    img = QImage(size, size, QImage.Format.Format_ARGB32)
    img.fill(Qt.GlobalColor.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    s = size / 256.0
    if margine != 1.0:
        p.translate(size * (1 - margine) / 2, size * (1 - margine) / 2)
        p.scale(margine, margine)

    if con_fondo:
        grad = QLinearGradient(QPointF(0, 0), QPointF(size, size))
        grad.setColorAt(0, QColor("#0f172a"))
        grad.setColorAt(1, QColor("#334155"))
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(grad)
        p.drawRoundedRect(QRectF(8 * s, 8 * s, 240 * s, 240 * s), 52 * s, 52 * s)
    p.setPen(Qt.PenStyle.NoPen)

    foglio = QPainterPath()
    foglio.moveTo(64 * s, 36 * s)
    foglio.lineTo(158 * s, 36 * s)
    foglio.lineTo(196 * s, 74 * s)
    foglio.lineTo(196 * s, 204 * s)
    foglio.quadTo(196 * s, 216 * s, 184 * s, 216 * s)
    foglio.lineTo(76 * s, 216 * s)
    foglio.quadTo(64 * s, 216 * s, 64 * s, 204 * s)
    foglio.closeSubpath()
    p.setBrush(QColor("white"))
    p.drawPath(foglio)

    piega = QPainterPath()
    piega.moveTo(158 * s, 36 * s)
    piega.lineTo(158 * s, 74 * s)
    piega.lineTo(196 * s, 74 * s)
    piega.closeSubpath()
    p.setBrush(QColor("#cbd5e1"))
    p.drawPath(piega)

    p.setBrush(QColor("#e2e8f0"))
    for i, larghezza in enumerate((80, 100, 64)):
        p.drawRoundedRect(QRectF(84 * s, (92 + i * 18) * s, larghezza * s, 8 * s), 4 * s, 4 * s)

    p.setBrush(QColor("#e11d48"))
    p.drawRoundedRect(QRectF(40 * s, 150 * s, 176 * s, 58 * s), 14 * s, 14 * s)
    font = QFont("Segoe UI")
    font.setBold(True)
    font.setPixelSize(max(6, int(44 * s)))
    p.setFont(font)
    p.setPen(QColor("white"))
    p.drawText(QRectF(40 * s, 150 * s, 176 * s, 58 * s), Qt.AlignmentFlag.AlignCenter, "PDF")
    p.end()
    return img


if __name__ == "__main__":
    app = QApplication(sys.argv)
    os.makedirs(ASSETS, exist_ok=True)
    disegna(1024).save(os.path.join(ASSETS, "icona.png"))
    # adattiva: solo il foglio, rimpicciolito perché Android ritaglia i bordi
    disegna(1024, con_fondo=False, margine=0.68).save(os.path.join(ASSETS, "icona-adattiva.png"))
    print("icone in", ASSETS)
