from PySide6 import QtWidgets, QtGui

def monospace_font(size: int = 11) -> QtGui.QFont:
    f = QtGui.QFont("Consolas")
    f.setStyleHint(QtGui.QFont.Monospace)
    f.setPointSize(size)
    return f

def make_badge(text: str, ok: bool) -> QtWidgets.QLabel:
    lbl = QtWidgets.QLabel(text)
    lbl.setAlignment(QtGui.Qt.AlignCenter)
    bg = "#173a2a" if ok else "#3a1b1b"
    bd = "#2ecc71" if ok else "#ff6b6b"
    lbl.setStyleSheet(f"""
        QLabel {{
            background: {bg};
            border: 1px solid {bd};
            border-radius: 10px;
            padding: 4px 10px;
            color: #e6e6e6;
        }}
    """)
    return lbl
