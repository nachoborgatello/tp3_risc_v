import struct
import threading
from PySide6 import QtCore, QtWidgets
from PySide6.QtWidgets import QFileDialog, QMessageBox

from debughost import DebugHost, MAGIC
from program_parser import parse_program_file
from pipe_decode import PIPE_WORDS, decode_pipe_words, signed32
from .widgets import monospace_font, make_badge

def dump_type_str(t: int) -> str:
    return {1: "STEP", 2: "RUN_END", 3: "MANUAL"}.get(t, f"UNKNOWN({t})")

def hexdump_lines(b: bytes, base: int = 0) -> list[str]:
    lines = []
    for i in range(0, len(b), 16):
        chunk = b[i:i+16]
        hexs = " ".join(f"{x:02x}" for x in chunk)
        lines.append(f"{base+i:04x}: {hexs}")
    return lines

class WorkerSignals(QtCore.QObject):
    log = QtCore.Signal(str)
    error = QtCore.Signal(str)
    dump = QtCore.Signal(dict)
    done = QtCore.Signal()

class ActionWorker(QtCore.QRunnable):
    def __init__(self, fn, *args, **kwargs):
        super().__init__()
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.signals = WorkerSignals()

    @QtCore.Slot()
    def run(self):
        try:
            res = self.fn(self.signals, *self.args, **self.kwargs)
            if isinstance(res, dict):
                self.signals.dump.emit(res)
        except Exception as e:
            self.signals.error.emit(str(e))
        finally:
            self.signals.done.emit()

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("RISC-V Debug Host (UART) – Basys3 (Qt)")
        self.resize(1350, 820)

        self.host: DebugHost | None = None
        self.threadpool = QtCore.QThreadPool.globalInstance()
        self.worker_lock = threading.Lock()

        self._build_ui()
        self._refresh_ports()
        self._set_connected(False)

    # ---------------- UI ----------------
    def _build_ui(self):
        root = QtWidgets.QWidget()
        self.setCentralWidget(root)

        main = QtWidgets.QVBoxLayout(root)
        main.setContentsMargins(14, 12, 14, 12)
        main.setSpacing(10)

        # --- Top bar ---
        bar = QtWidgets.QHBoxLayout()
        main.addLayout(bar)

        self.port_cb = QtWidgets.QComboBox()
        self.port_cb.setMinimumWidth(160)
        bar.addWidget(QtWidgets.QLabel("Puerto"))
        bar.addWidget(self.port_cb)

        self.baud_edit = QtWidgets.QLineEdit("115200")
        self.baud_edit.setMaximumWidth(120)
        bar.addWidget(QtWidgets.QLabel("Baud"))
        bar.addWidget(self.baud_edit)

        self.dm_edit = QtWidgets.QLineEdit("64")
        self.dm_edit.setMaximumWidth(80)
        bar.addWidget(QtWidgets.QLabel("DM bytes"))
        bar.addWidget(self.dm_edit)

        self.btn_refresh = QtWidgets.QPushButton("Refrescar")
        self.btn_refresh.clicked.connect(self._refresh_ports)
        bar.addWidget(self.btn_refresh)

        bar.addStretch(1)

        self.btn_connect = QtWidgets.QPushButton("Conectar")
        self.btn_connect.clicked.connect(self.connect)
        bar.addWidget(self.btn_connect)

        self.btn_disconnect = QtWidgets.QPushButton("Desconectar")
        self.btn_disconnect.clicked.connect(self.disconnect)
        bar.addWidget(self.btn_disconnect)

        # --- Actions ---
        actions = QtWidgets.QHBoxLayout()
        main.addLayout(actions)

        self.btn_dump = QtWidgets.QPushButton("Dump (D)")
        self.btn_step = QtWidgets.QPushButton("Step (S)")
        self.btn_run  = QtWidgets.QPushButton("Run (G)")
        self.btn_rst  = QtWidgets.QPushButton("Reset fetch (R)")
        self.btn_load = QtWidgets.QPushButton("Cargar programa…")

        self.btn_dump.clicked.connect(lambda: self.run_action("dump"))
        self.btn_step.clicked.connect(lambda: self.run_action("step"))
        self.btn_run.clicked.connect(lambda: self.run_action("run"))
        self.btn_rst.clicked.connect(lambda: self.run_action("reset"))
        self.btn_load.clicked.connect(self.load_program_dialog)

        for b in [self.btn_dump, self.btn_step, self.btn_run, self.btn_rst, self.btn_load]:
            actions.addWidget(b)

        actions.addStretch(1)

        # --- Split content ---
        split = QtWidgets.QSplitter()
        split.setChildrenCollapsible(False)
        main.addWidget(split, 1)

        left = QtWidgets.QWidget()
        right = QtWidgets.QWidget()
        split.addWidget(left)
        split.addWidget(right)
        split.setStretchFactor(0, 2)
        split.setStretchFactor(1, 1)

        # Left layout
        L = QtWidgets.QVBoxLayout(left)
        L.setContentsMargins(0, 0, 0, 0)
        L.setSpacing(10)

        # Status card
        st = QtWidgets.QGroupBox("Estado del último dump")
        stl = QtWidgets.QHBoxLayout(st)

        self.badge_pipe = make_badge("PIPE: ?", True)
        self.badge_halt = make_badge("HALT: ?", True)
        self.lbl_status = QtWidgets.QLabel("(sin dump)")
        self.lbl_status.setFont(monospace_font(11))

        stl.addWidget(self.badge_pipe)
        stl.addWidget(self.badge_halt)
        stl.addSpacing(12)
        stl.addWidget(self.lbl_status, 1)

        L.addWidget(st)

        # IMEM programming card
        prog = QtWidgets.QGroupBox("Programar IMEM (P)")
        pl = QtWidgets.QGridLayout(prog)

        self.addr_edit = QtWidgets.QLineEdit("0x00000000")
        self.data_edit = QtWidgets.QLineEdit("0x00000013")
        self.seq_edit  = QtWidgets.QLineEdit("0x00000013 0x00100073")

        self.btn_prog = QtWidgets.QPushButton("Programar word")
        self.btn_prog.clicked.connect(lambda: self.run_action("prog"))

        self.btn_progseq = QtWidgets.QPushButton("Programar secuencia")
        self.btn_progseq.clicked.connect(lambda: self.run_action("progseq"))

        pl.addWidget(QtWidgets.QLabel("Addr (hex)"), 0, 0)
        pl.addWidget(self.addr_edit, 0, 1)
        pl.addWidget(QtWidgets.QLabel("Data (hex)"), 0, 2)
        pl.addWidget(self.data_edit, 0, 3)
        pl.addWidget(self.btn_prog, 0, 4)

        pl.addWidget(QtWidgets.QLabel("Secuencia (words)"), 1, 0)
        pl.addWidget(self.seq_edit, 1, 1, 1, 3)
        pl.addWidget(self.btn_progseq, 1, 4)

        L.addWidget(prog)

        # Tabs: Regs / Pipeline / Raw
        self.tabs = QtWidgets.QTabWidget()
        L.addWidget(self.tabs, 1)

        # --- Regs tab ---
        regs_tab = QtWidgets.QWidget()
        regs_l = QtWidgets.QVBoxLayout(regs_tab)

        self.reg_table = QtWidgets.QTableWidget(32, 3)
        self.reg_table.setHorizontalHeaderLabels(["Reg", "Hex", "Dec (signed)"])
        self.reg_table.verticalHeader().setVisible(False)
        self.reg_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.reg_table.setSelectionMode(QtWidgets.QAbstractItemView.NoSelection)
        self.reg_table.setFont(monospace_font(10))
        self.reg_table.horizontalHeader().setStretchLastSection(True)
        self.reg_table.setColumnWidth(0, 70)
        self.reg_table.setColumnWidth(1, 140)

        for i in range(32):
            self.reg_table.setItem(i, 0, QtWidgets.QTableWidgetItem(f"x{i}"))
            self.reg_table.setItem(i, 1, QtWidgets.QTableWidgetItem("0x00000000"))
            self.reg_table.setItem(i, 2, QtWidgets.QTableWidgetItem("0"))

        regs_l.addWidget(self.reg_table)
        self.tabs.addTab(regs_tab, "Registros")

        # --- Pipeline tab ---
        pipe_tab = QtWidgets.QWidget()
        pipe_l = QtWidgets.QVBoxLayout(pipe_tab)

        self.pipe_summary = QtWidgets.QLabel("(sin dump)")
        self.pipe_summary.setFont(monospace_font(10))
        pipe_l.addWidget(self.pipe_summary)

        grid = QtWidgets.QGridLayout()
        pipe_l.addLayout(grid, 1)

        self.ifid_tbl = self._make_kv_table("IF/ID")
        self.idex_tbl = self._make_kv_table("ID/EX")
        self.exmem_tbl = self._make_kv_table("EX/MEM")
        self.memwb_tbl = self._make_kv_table("MEM/WB")

        grid.addWidget(self.ifid_tbl, 0, 0)
        grid.addWidget(self.idex_tbl, 0, 1)
        grid.addWidget(self.exmem_tbl, 1, 0)
        grid.addWidget(self.memwb_tbl, 1, 1)
        grid.setColumnStretch(0, 1)
        grid.setColumnStretch(1, 1)
        grid.setRowStretch(0, 1)
        grid.setRowStretch(1, 1)

        self.tabs.addTab(pipe_tab, "Pipeline")

        # --- Raw tab ---
        raw_tab = QtWidgets.QWidget()
        raw_l = QtWidgets.QVBoxLayout(raw_tab)
        self.raw_text = QtWidgets.QPlainTextEdit()
        self.raw_text.setReadOnly(True)
        self.raw_text.setFont(monospace_font(10))
        raw_l.addWidget(self.raw_text)
        self.tabs.addTab(raw_tab, "RAW")

        # Right layout
        R = QtWidgets.QVBoxLayout(right)
        R.setContentsMargins(0, 0, 0, 0)
        R.setSpacing(10)

        mem = QtWidgets.QGroupBox("DMEM Hexdump")
        ml = QtWidgets.QVBoxLayout(mem)
        self.mem_text = QtWidgets.QPlainTextEdit()
        self.mem_text.setReadOnly(True)
        self.mem_text.setFont(monospace_font(10))
        ml.addWidget(self.mem_text)
        R.addWidget(mem, 2)

        log = QtWidgets.QGroupBox("Log")
        ll = QtWidgets.QVBoxLayout(log)
        self.log_text = QtWidgets.QPlainTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setFont(monospace_font(9))
        ll.addWidget(self.log_text)
        R.addWidget(log, 1)

        self.statusBar().showMessage("Listo.")

    def _make_kv_table(self, title: str) -> QtWidgets.QGroupBox:
        box = QtWidgets.QGroupBox(title)
        lay = QtWidgets.QVBoxLayout(box)
        tbl = QtWidgets.QTableWidget(0, 2)
        tbl.setHorizontalHeaderLabels(["Señal", "Valor"])
        tbl.verticalHeader().setVisible(False)
        tbl.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        tbl.setSelectionMode(QtWidgets.QAbstractItemView.NoSelection)
        tbl.setFont(monospace_font(10))
        tbl.setColumnWidth(0, 120)
        tbl.horizontalHeader().setStretchLastSection(True)
        lay.addWidget(tbl)
        box._tbl = tbl  # hack simple para acceder
        return box

    def _set_kv_rows(self, box: QtWidgets.QGroupBox, rows: list[tuple[str, str]]):
        tbl: QtWidgets.QTableWidget = box._tbl
        tbl.setRowCount(len(rows))
        for r, (k, v) in enumerate(rows):
            tbl.setItem(r, 0, QtWidgets.QTableWidgetItem(k))
            tbl.setItem(r, 1, QtWidgets.QTableWidgetItem(v))

    # ---------------- helpers ----------------
    def log(self, msg: str):
        self.log_text.appendPlainText(msg)
        self.statusBar().showMessage(msg, 2500)

    def _set_connected(self, connected: bool):
        self.btn_connect.setEnabled(not connected)
        self.btn_disconnect.setEnabled(connected)

        for b in [self.btn_dump, self.btn_step, self.btn_run, self.btn_rst, self.btn_load,
                  self.btn_prog, self.btn_progseq]:
            b.setEnabled(connected)

    def _refresh_ports(self):
        import serial.tools.list_ports
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_cb.clear()
        self.port_cb.addItems(ports)
        if ports:
            self.port_cb.setCurrentIndex(0)

    # ---------------- connect/disconnect ----------------
    def connect(self):
        if self.host is not None:
            return
        port = self.port_cb.currentText().strip()
        if not port:
            QMessageBox.critical(self, "Error", "Elegí un puerto.")
            return

        try:
            baud = int(self.baud_edit.text())
            dm = int(self.dm_edit.text())
        except ValueError:
            QMessageBox.critical(self, "Error", "Baud y DM bytes deben ser números.")
            return

        try:
            self.host = DebugHost(port, baud, pipe_words=PIPE_WORDS, dm_dump_bytes=dm)
            self._set_connected(True)
            self.log(f"[INFO] Conectado a {port} @ {baud}, DM={dm}, PIPE_WORDS={PIPE_WORDS}")
        except Exception as e:
            self.host = None
            QMessageBox.critical(self, "Error", f"No pude conectar: {e}")

    def disconnect(self):
        if self.host is None:
            return
        try:
            self.host.close()
        finally:
            self.host = None
            self._set_connected(False)
            self.log("[INFO] Desconectado")

    # ---------------- load program ----------------
    def load_program_dialog(self):
        if self.host is None:
            return
        path, _ = QFileDialog.getOpenFileName(
            self, "Seleccionar programa (.mem/.hex)", "", "Mem/Hex (*.mem *.hex *.txt);;Todos (*.*)"
        )
        if not path:
            return
        self.run_load_program(path)

    def run_load_program(self, path: str):
        def fn(sig: WorkerSignals):
            with self.worker_lock:
                items = parse_program_file(path)
                if not items:
                    raise ValueError("El archivo no tiene words parseables.")

                sig.log.emit(f"[INFO] Cargando programa: {path}")
                sig.log.emit(f"[INFO] Words a programar: {len(items)}")

                for k, (addr, word) in enumerate(items):
                    self.host.program_word(addr, word)
                    if (k + 1) % 64 == 0:
                        sig.log.emit(f"[INFO] ... {k+1}/{len(items)}")

                sig.log.emit("[OK] Programa cargado.")
                return {}

        self._run_worker(fn)

    # ---------------- actions ----------------
    def run_action(self, action: str):
        if self.host is None:
            return

        def parse_frame(frame: bytes) -> dict:
            if len(frame) != self.host.frame_len:
                raise ValueError("Frame incompleto")

            magic, dump_type, flags, pad = frame[0], frame[1], frame[2], frame[3]
            if magic != MAGIC:
                raise ValueError("MAGIC inválido")

            pipe_empty = (flags >> 1) & 1
            halt_seen  = (flags >> 0) & 1

            off = 4
            pc = struct.unpack_from("<I", frame, off)[0]
            off += 4

            pipe_words = list(struct.unpack_from(f"<{PIPE_WORDS}I", frame, off))
            off += PIPE_WORDS * 4

            regs = list(struct.unpack_from("<32I", frame, off))
            off += 32 * 4

            mem = frame[off: off + self.host.dm_dump_bytes]
            pd = decode_pipe_words(pipe_words)

            return {
                "dump_type": dump_type,
                "flags": flags,
                "pipe_empty": pipe_empty,
                "halt_seen": halt_seen,
                "pad": pad,
                "pc": pc,
                "pipe_words": pipe_words,
                "pipe_decoded": pd,
                "regs": regs,
                "mem": mem,
            }

        def fn(sig: WorkerSignals):
            with self.worker_lock:
                if action == "dump":
                    sig.log.emit("[TX] D (dump)")
                    self.host.send_cmd("D")
                    frame = self.host.wait_dump(timeout_s=5.0)
                    return parse_frame(frame)

                if action == "step":
                    sig.log.emit("[TX] S (step)")
                    self.host.send_cmd("S")
                    frame = self.host.wait_dump(timeout_s=8.0)
                    return parse_frame(frame)

                if action == "run":
                    sig.log.emit("[TX] G (run)")
                    self.host.send_cmd("G")
                    frame = self.host.wait_dump(timeout_s=12.0)
                    return parse_frame(frame)

                if action == "reset":
                    sig.log.emit("[TX] R (reset fetch)")
                    self.host.send_cmd("R")
                    return {}

                if action == "prog":
                    addr = int(self.addr_edit.text(), 0)
                    data = int(self.data_edit.text(), 0)
                    sig.log.emit(f"[TX] P addr=0x{addr:08x} data=0x{data:08x}")
                    self.host.program_word(addr, data)
                    return {}

                if action == "progseq":
                    base = int(self.addr_edit.text(), 0)
                    words_s = self.seq_edit.text().strip()
                    if not words_s:
                        raise ValueError("Secuencia vacía")
                    words = [int(tok, 0) for tok in words_s.split()]
                    sig.log.emit(f"[TX] P(seq) base=0x{base:08x} n={len(words)}")
                    for i, w in enumerate(words):
                        self.host.program_word(base + 4*i, w)
                    return {}

                return {}

        self._run_worker(fn)

    def _run_worker(self, fn):
        w = ActionWorker(fn)
        w.signals.log.connect(self.log)
        w.signals.error.connect(lambda s: QMessageBox.critical(self, "Error", s))
        w.signals.dump.connect(self.apply_dump)
        self.threadpool.start(w)

    # ---------------- apply dump ----------------
    def apply_dump(self, d: dict):
        t = dump_type_str(d["dump_type"])
        flags = d["flags"]
        pe = d["pipe_empty"]
        hs = d["halt_seen"]
        pc = d["pc"]
        pad = d["pad"]

        # badges
        self.badge_pipe.setText(f"PIPE_EMPTY: {pe}")
        self.badge_halt.setText(f"HALT_SEEN: {hs}")
        self.badge_pipe.setStyleSheet(self.badge_pipe.styleSheet().replace("#173a2a", "#173a2a" if pe else "#3a1b1b"))
        self.badge_halt.setStyleSheet(self.badge_halt.styleSheet().replace("#173a2a", "#173a2a" if not hs else "#3a1b1b"))

        self.lbl_status.setText(
            f"type={t}  flags=0x{flags:02x}  pc=0x{pc:08x}  pad=0x{pad:02x}"
        )
        self.log(f"[RX] DUMP type={t} flags=0x{flags:02x} pc=0x{pc:08x}")

        # regs
        regs = d["regs"]
        for i in range(32):
            val = regs[i] & 0xFFFFFFFF
            self.reg_table.item(i, 1).setText(f"0x{val:08x}")
            self.reg_table.item(i, 2).setText(str(signed32(val)))

        # mem hexdump
        self.mem_text.setPlainText("\n".join(hexdump_lines(d["mem"], base=0)))

        # pipe
        pd = d.get("pipe_decoded", {})
        if "error" in pd:
            self.pipe_summary.setText(f"[PIPE] ERROR: {pd['error']}")
            return

        ifid = pd["ifid"]; idex = pd["idex"]; exmem = pd["exmem"]; memwb = pd["memwb"]
        self.pipe_summary.setText(
            f"IF/ID v={ifid['valid']} | ID/EX v={idex['ctrl']['valid']} | EX/MEM v={exmem['ctrl']['valid']} | MEM/WB v={memwb['ctrl']['valid']}"
        )

        self._set_kv_rows(self.ifid_tbl, [
            ("valid", str(ifid["valid"])),
            ("pc", f"0x{ifid['pc']:08x}"),
            ("pc+4", f"0x{ifid['pc4']:08x}"),
            ("instr", f"0x{ifid['instr']:08x}"),
        ])

        c = idex["ctrl"]
        self._set_kv_rows(self.idex_tbl, [
            ("valid", str(c["valid"])),
            ("pc", f"0x{idex['pc']:08x}"),
            ("pc+4", f"0x{idex['pc4']:08x}"),
            ("rs1_data", f"0x{idex['rs1_data']:08x} ({signed32(idex['rs1_data'])})"),
            ("rs2_data", f"0x{idex['rs2_data']:08x} ({signed32(idex['rs2_data'])})"),
            ("imm", f"0x{idex['imm']:08x} ({signed32(idex['imm'])})"),
            ("rs1/rs2/rd", f"{idex['rs1']}/{idex['rs2']}/{idex['rd']}"),
            ("f3/f7", f"{idex['funct3']}/{idex['funct7']}"),
            ("ctrl", f"RW={c['reg_write']} MR={c['mem_read']} MW={c['mem_write']} "
                     f"M2R={c['mem_to_reg']} AS={c['alu_src']} ALUop={c['alu_op']} "
                     f"BR={c['branch']} J={c['jump']} JALR={c['jalr']} PC4={c['wb_sel_pc4']}"),
        ])

        c = exmem["ctrl"]
        self._set_kv_rows(self.exmem_tbl, [
            ("valid", str(c["valid"])),
            ("alu_result", f"0x{exmem['alu_result']:08x} ({signed32(exmem['alu_result'])})"),
            ("rs2_pass", f"0x{exmem['rs2_pass']:08x} ({signed32(exmem['rs2_pass'])})"),
            ("br_target", f"0x{exmem['branch_target']:08x}"),
            ("pc+4", f"0x{exmem['pc4']:08x}"),
            ("rd/f3", f"{exmem['rd']}/{exmem['funct3']}"),
            ("ctrl", f"RW={c['reg_write']} MR={c['mem_read']} MW={c['mem_write']} "
                     f"M2R={c['mem_to_reg']} BT={c['branch_taken']} PC4={c['wb_sel_pc4']}"),
        ])

        c = memwb["ctrl"]
        self._set_kv_rows(self.memwb_tbl, [
            ("valid", str(c["valid"])),
            ("mem_data", f"0x{memwb['mem_read_data']:08x} ({signed32(memwb['mem_read_data'])})"),
            ("alu_result", f"0x{memwb['alu_result']:08x} ({signed32(memwb['alu_result'])})"),
            ("pc+4", f"0x{memwb['pc4']:08x}"),
            ("rd", str(memwb["rd"])),
            ("ctrl", f"RW={c['reg_write']} M2R={c['mem_to_reg']} PC4={c['wb_sel_pc4']}"),
        ])

        # RAW view
        raw_lines = []
        raw_lines.append(f"PC=0x{d['pc']:08x}  type={t} flags=0x{flags:02x}")
        raw_lines.append("")
        raw_lines.append("PIPE words (w0..w22):")
        for i, w in enumerate(d["pipe_words"]):
            raw_lines.append(f"  w{i:02d} = 0x{w:08x}")
        self.raw_text.setPlainText("\n".join(raw_lines))
