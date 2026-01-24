DARK_QSS = """
* { font-family: Segoe UI, Inter, Arial; font-size: 12px; }
QMainWindow { background: #0f1115; color: #e6e6e6; }
QWidget { background: #0f1115; color: #e6e6e6; }

QGroupBox {
  border: 1px solid #2a2f3a;
  border-radius: 10px;
  margin-top: 10px;
  padding: 10px;
}
QGroupBox::title {
  subcontrol-origin: margin;
  left: 10px;
  padding: 0 6px;
  color: #cfd6e6;
}

QLineEdit, QComboBox, QSpinBox, QTextEdit, QPlainTextEdit {
  background: #151924;
  border: 1px solid #2a2f3a;
  border-radius: 8px;
  padding: 6px;
  selection-background-color: #2f81f7;
}

QPushButton {
  background: #1a2333;
  border: 1px solid #2a2f3a;
  border-radius: 10px;
  padding: 8px 10px;
}
QPushButton:hover { background: #212c40; }
QPushButton:pressed { background: #141b28; }
QPushButton:disabled { color: #7c879b; background: #121622; border-color: #232838; }

QTabWidget::pane {
  border: 1px solid #2a2f3a;
  border-radius: 10px;
  padding: 4px;
}
QTabBar::tab {
  background: #131826;
  border: 1px solid #2a2f3a;
  border-bottom: none;
  border-top-left-radius: 10px;
  border-top-right-radius: 10px;
  padding: 8px 14px;
  margin-right: 4px;
}
QTabBar::tab:selected { background: #1a2333; }

QTableWidget {
  background: #0f1115;
  gridline-color: #2a2f3a;
  border: 1px solid #2a2f3a;
  border-radius: 10px;
}
QHeaderView::section {
  background: #131826;
  border: 1px solid #2a2f3a;
  padding: 6px;
  color: #cfd6e6;
}
QTableWidget::item { padding: 6px; }

QStatusBar { background: #0f1115; border-top: 1px solid #2a2f3a; }
"""
