import sys
from PySide6 import QtWidgets
from ui.main_window import MainWindow
from ui.styles import DARK_QSS

def main():
    app = QtWidgets.QApplication(sys.argv)
    app.setStyleSheet(DARK_QSS)
    w = MainWindow()
    w.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
