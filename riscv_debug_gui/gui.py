import struct
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

import serial
import serial.tools.list_ports

MAGIC = 0xD0
PIPE_WORDS = 23  # debe coincidir con cpu_top (dbg_pipe_flat)

def u32_le(x: int) -> bytes:
    return struct.pack("<I", x & 0xFFFFFFFF)

def read_exact(ser: serial.Serial, n: int) -> bytes:
    data = bytearray()
    while len(data) < n:
        chunk = ser.read(n - len(data))
        if not chunk:
            raise TimeoutError(f"Timeout leyendo {n} bytes (llegaron {len(data)})")
        data += chunk
    return bytes(data)

def sync_to_magic(ser: serial.Serial, deadline_s: float) -> None:
    while time.time() < deadline_s:
        b = ser.read(1)
        if b and b[0] == MAGIC:
            return
    raise TimeoutError("Timeout esperando MAGIC 0xD0")

def dump_type_str(t: int) -> str:
    return {1: "STEP", 2: "RUN_END", 3: "MANUAL"}.get(t, f"UNKNOWN({t})")

def hexdump_lines(b: bytes, base: int = 0) -> list[str]:
    lines = []
    for i in range(0, len(b), 16):
        chunk = b[i:i+16]
        hexs = " ".join(f"{x:02x}" for x in chunk)
        lines.append(f"{base+i:04x}: {hexs}")
    return lines

def _strip_comment(line: str) -> str:
    # soporta // y #
    if "//" in line:
        line = line.split("//", 1)[0]
    if "#" in line:
        line = line.split("#", 1)[0]
    return line.strip()

def parse_program_file(path: str) -> list[tuple[int, int]]:
    """
    Devuelve lista de (addr_byte, word32).
    Formatos aceptados:
      - Una palabra hex por línea: 00000013 / 0x00000013
      - Con marcador de dirección estilo readmemh: @00000040
        (la dirección es en BYTES; si está en words, igual te funciona si vos la ponés ya *4)
      - ADDR:DATA
    """
    items: list[tuple[int, int]] = []
    base = 0  # addr byte actual
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            s = _strip_comment(raw)
            if not s:
                continue

            if s.startswith("@"):
                addr_s = s[1:].strip()
                base = int(addr_s, 16) if addr_s.lower().startswith("0x") is False else int(addr_s, 0)
                continue

            if ":" in s:
                a_s, d_s = s.split(":", 1)
                a_s = a_s.strip()
                d_s = d_s.strip()
                addr = int(a_s, 0) if a_s.lower().startswith("0x") else int(a_s, 16)
                word = int(d_s, 0) if d_s.lower().startswith("0x") else int(d_s, 16)
                items.append((addr & 0xFFFFFFFF, word & 0xFFFFFFFF))
                continue

            word = int(s, 0) if s.lower().startswith("0x") else int(s, 16)
            items.append((base & 0xFFFFFFFF, word & 0xFFFFFFFF))
            base = (base + 4) & 0xFFFFFFFF

    return items

def _signed32(x: int) -> int:
    x &= 0xFFFFFFFF
    return x if x < 0x80000000 else x - 0x100000000

def decode_pipe_words(pw: list[int]) -> dict:
    """
    Decodifica el layout definido en cpu_top:
      w0  pc_ifid
      w1  pc_plus4_ifid
      w2  instr_ifid
      w3  {valid_ifid}
      w4  pc_idex
      w5  pc_plus4_idex
      w6  rs1_data_idex
      w7  rs2_data_idex
      w8  imm_idex
      w9  {funct7,funct3,rs2,rs1,rd,7'b0}
      w10 control_idex bits
      w11 alu_result_exmem
      w12 rs2_pass_exmem
      w13 branch_target_exmem
      w14 pc_plus4_exmem
      w15 {funct3,rd}
      w16 control_exmem bits
      w17 mem_read_data_mwb
      w18 alu_result_mwb
      w19 pc_plus4_mwb
      w20 rd_mwb
      w21 control_memwb bits
      w22 reservado
    """
    if len(pw) != PIPE_WORDS:
        return {"error": f"pipe_words len={len(pw)} != {PIPE_WORDS}"}

    w = pw

    # IF/ID
    valid_ifid = (w[3] & 0x1)

    # ID/EX fields
    w9 = w[9]
    funct7 = (w9 >> 25) & 0x7F
    funct3 = (w9 >> 22) & 0x7
    rs2    = (w9 >> 17) & 0x1F
    rs1    = (w9 >> 12) & 0x1F
    rd     = (w9 >> 7)  & 0x1F

    c10 = w[10]
    valid_idex     = (c10 >> 0) & 1
    reg_write_idex = (c10 >> 1) & 1
    mem_to_reg     = (c10 >> 2) & 1
    mem_read       = (c10 >> 3) & 1
    mem_write      = (c10 >> 4) & 1
    branch         = (c10 >> 5) & 1
    alu_src        = (c10 >> 6) & 1
    alu_op         = (c10 >> 7) & 0x3
    jump           = (c10 >> 9) & 1
    jalr           = (c10 >> 10) & 1
    wb_sel_pc4     = (c10 >> 11) & 1

    # EX/MEM
    w15 = w[15]
    funct3_exmem = (w15 >> 10) & 0x7
    rd_exmem     = (w15 >> 5) & 0x1F

    c16 = w[16]
    valid_exmem     = (c16 >> 0) & 1
    reg_write_exmem = (c16 >> 1) & 1
    mem_to_reg_exmem= (c16 >> 2) & 1
    mem_read_exmem  = (c16 >> 3) & 1
    mem_write_exmem = (c16 >> 4) & 1
    branch_taken    = (c16 >> 5) & 1
    wb_sel_pc4_exmem= (c16 >> 6) & 1

    # MEM/WB
    rd_mwb = w[20] & 0x1F
    c21 = w[21]
    valid_memwb     = (c21 >> 0) & 1
    reg_write_memwb = (c21 >> 1) & 1
    mem_to_reg_memwb= (c21 >> 2) & 1
    wb_sel_pc4_memwb= (c21 >> 3) & 1

    return {
        "ifid": {
            "pc": w[0],
            "pc4": w[1],
            "instr": w[2],
            "valid": valid_ifid,
        },
        "idex": {
            "pc": w[4],
            "pc4": w[5],
            "rs1_data": w[6],
            "rs2_data": w[7],
            "imm": w[8],
            "rs1": rs1,
            "rs2": rs2,
            "rd": rd,
            "funct3": funct3,
            "funct7": funct7,
            "ctrl": {
                "valid": valid_idex,
                "reg_write": reg_write_idex,
                "mem_to_reg": mem_to_reg,
                "mem_read": mem_read,
                "mem_write": mem_write,
                "branch": branch,
                "alu_src": alu_src,
                "alu_op": alu_op,
                "jump": jump,
                "jalr": jalr,
                "wb_sel_pc4": wb_sel_pc4,
            }
        },
        "exmem": {
            "alu_result": w[11],
            "rs2_pass": w[12],
            "branch_target": w[13],
            "pc4": w[14],
            "rd": rd_exmem,
            "funct3": funct3_exmem,
            "ctrl": {
                "valid": valid_exmem,
                "reg_write": reg_write_exmem,
                "mem_to_reg": mem_to_reg_exmem,
                "mem_read": mem_read_exmem,
                "mem_write": mem_write_exmem,
                "branch_taken": branch_taken,
                "wb_sel_pc4": wb_sel_pc4_exmem,
            }
        },
        "memwb": {
            "mem_read_data": w[17],
            "alu_result": w[18],
            "pc4": w[19],
            "rd": rd_mwb,
            "ctrl": {
                "valid": valid_memwb,
                "reg_write": reg_write_memwb,
                "mem_to_reg": mem_to_reg_memwb,
                "wb_sel_pc4": wb_sel_pc4_memwb,
            }
        },
        "raw_words": w,
    }

class DebugHost:
    def __init__(self, port: str, baud: int, dm_dump_bytes: int = 64, timeout_s: float = 0.2):
        self.dm_dump_bytes = dm_dump_bytes
        self.frame_len = 4 + 4 + PIPE_WORDS*4 + 32*4 + dm_dump_bytes
        self.ser = serial.Serial(port, baud, timeout=timeout_s)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass

    def send_cmd(self, c: str):
        self.ser.write(c.encode("ascii"))

    def program_word(self, addr: int, data: int):
        self.send_cmd("P")
        self.ser.write(u32_le(addr))
        self.ser.write(u32_le(data))

    def wait_dump(self, timeout_s: float = 5.0):
        deadline = time.time() + timeout_s
        sync_to_magic(self.ser, deadline)
        rest = read_exact(self.ser, self.frame_len - 1)
        frame = bytes([MAGIC]) + rest
        return self._parse(frame)

    def _parse(self, frame: bytes) -> dict:
        if len(frame) != self.frame_len:
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
        off += PIPE_WORDS*4

        regs = list(struct.unpack_from("<32I", frame, off))
        off += 32*4

        mem = frame[off:off + self.dm_dump_bytes]

        pipe_dec = decode_pipe_words(pipe_words)

        return {
            "dump_type": dump_type,
            "flags": flags,
            "pipe_empty": pipe_empty,
            "halt_seen": halt_seen,
            "pad": pad,
            "pc": pc,
            "pipe_words": pipe_words,
            "pipe_decoded": pipe_dec,
            "regs": regs,
            "mem": mem
        }

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("RISC-V Debug Host (UART) - Basys3")
        self.geometry("1280x780")

        self.host: DebugHost | None = None
        self.worker_lock = threading.Lock()

        self._build_ui()
        self._refresh_ports()

        self.protocol("WM_DELETE_WINDOW", self.on_close)

    # ---------------- UI ----------------
    def _build_ui(self):
        top = ttk.Frame(self, padding=10)
        top.pack(fill="x")

        ttk.Label(top, text="Puerto:").pack(side="left")
        self.port_cb = ttk.Combobox(top, width=18, values=[])
        self.port_cb.pack(side="left", padx=6)

        ttk.Label(top, text="Baud:").pack(side="left")
        self.baud_var = tk.StringVar(value="115200")
        self.baud_entry = ttk.Entry(top, width=10, textvariable=self.baud_var)
        self.baud_entry.pack(side="left", padx=6)

        ttk.Label(top, text="DM bytes:").pack(side="left")
        self.dm_var = tk.StringVar(value="64")
        self.dm_entry = ttk.Entry(top, width=6, textvariable=self.dm_var)
        self.dm_entry.pack(side="left", padx=6)

        self.btn_refresh = ttk.Button(top, text="Refrescar", command=self._refresh_ports)
        self.btn_refresh.pack(side="left", padx=6)

        self.btn_connect = ttk.Button(top, text="Conectar", command=self.connect)
        self.btn_connect.pack(side="left", padx=6)

        self.btn_disconnect = ttk.Button(top, text="Desconectar", command=self.disconnect, state="disabled")
        self.btn_disconnect.pack(side="left", padx=6)

        # Actions
        actions = ttk.Frame(self, padding=(10, 0, 10, 10))
        actions.pack(fill="x")

        self.btn_dump = ttk.Button(actions, text="Dump (D)", command=lambda: self.run_action("dump"), state="disabled")
        self.btn_step = ttk.Button(actions, text="Step (S)", command=lambda: self.run_action("step"), state="disabled")
        self.btn_run  = ttk.Button(actions, text="Run (G)",  command=lambda: self.run_action("run"),  state="disabled")
        self.btn_rst  = ttk.Button(actions, text="Reset fetch (R)", command=lambda: self.run_action("reset"), state="disabled")
        self.btn_load = ttk.Button(actions, text="Cargar programa…", command=self.load_program_dialog, state="disabled")

        for b in [self.btn_dump, self.btn_step, self.btn_run, self.btn_rst, self.btn_load]:
            b.pack(side="left", padx=6)

        # Program IMEM
        prog = ttk.LabelFrame(self, text="Programar IMEM (P)", padding=10)
        prog.pack(fill="x", padx=10, pady=(0,10))

        ttk.Label(prog, text="Addr (hex):").grid(row=0, column=0, sticky="w")
        ttk.Label(prog, text="Data (hex):").grid(row=0, column=2, sticky="w")
        self.addr_var = tk.StringVar(value="0x00000000")
        self.data_var = tk.StringVar(value="0x00000013")
        self.addr_entry = ttk.Entry(prog, width=14, textvariable=self.addr_var)
        self.data_entry = ttk.Entry(prog, width=14, textvariable=self.data_var)
        self.addr_entry.grid(row=0, column=1, padx=6)
        self.data_entry.grid(row=0, column=3, padx=6)

        self.btn_prog = ttk.Button(prog, text="Programar word", command=lambda: self.run_action("prog"), state="disabled")
        self.btn_prog.grid(row=0, column=4, padx=8)

        ttk.Label(prog, text="Secuencia (words hex separados por espacio):").grid(row=1, column=0, columnspan=2, sticky="w", pady=(8,0))
        self.seq_var = tk.StringVar(value="0x00000013 0x00100073")
        self.seq_entry = ttk.Entry(prog, width=60, textvariable=self.seq_var)
        self.seq_entry.grid(row=1, column=2, columnspan=2, sticky="we", padx=6, pady=(8,0))
        self.btn_progseq = ttk.Button(prog, text="Programar secuencia desde Addr", command=lambda: self.run_action("progseq"), state="disabled")
        self.btn_progseq.grid(row=1, column=4, padx=8, pady=(8,0))

        prog.columnconfigure(3, weight=1)

        # Status + views
        mid = ttk.Frame(self, padding=(10,0,10,10))
        mid.pack(fill="both", expand=True)

        left = ttk.Frame(mid)
        left.pack(side="left", fill="both", expand=True, padx=(0,10))

        right = ttk.Frame(mid)
        right.pack(side="left", fill="both", expand=True)

        # Status
        st = ttk.LabelFrame(left, text="Estado del último dump", padding=10)
        st.pack(fill="x")

        self.status_var = tk.StringVar(value="(sin dump)")
        ttk.Label(st, textvariable=self.status_var, font=("Consolas", 11)).pack(anchor="w")

        # Notebook: Regs / Pipe
        nb = ttk.Notebook(left)
        nb.pack(fill="both", expand=True, pady=(10,0))

        # -------- Registros tab --------
        regs_tab = ttk.Frame(nb)
        nb.add(regs_tab, text="Registros")

        regs = ttk.LabelFrame(regs_tab, text="Registros x0..x31", padding=10)
        regs.pack(fill="both", expand=True)

        self.reg_tree = ttk.Treeview(regs, columns=("reg","hex","dec"), show="headings", height=14)
        self.reg_tree.heading("reg", text="Reg")
        self.reg_tree.heading("hex", text="Hex")
        self.reg_tree.heading("dec", text="Dec (signed)")
        self.reg_tree.column("reg", width=60, anchor="center")
        self.reg_tree.column("hex", width=120, anchor="w")
        self.reg_tree.column("dec", width=140, anchor="w")
        self.reg_tree.pack(fill="both", expand=True)

        for i in range(32):
            self.reg_tree.insert("", "end", values=(f"x{i}", "0x00000000", "0"))

        # -------- Pipeline tab --------
        pipe_tab = ttk.Frame(nb)
        nb.add(pipe_tab, text="Pipeline")

        pipe_top = ttk.Frame(pipe_tab, padding=10)
        pipe_top.pack(fill="x")

        self.pipe_status_var = tk.StringVar(value="(sin dump)")
        ttk.Label(pipe_top, textvariable=self.pipe_status_var, font=("Consolas", 10)).pack(anchor="w")

        pipe_tables = ttk.Frame(pipe_tab, padding=(10,0,10,10))
        pipe_tables.pack(fill="both", expand=True)

        # IF/ID
        self.ifid_tree = ttk.Treeview(pipe_tables, columns=("sig","val"), show="headings", height=5)
        self.ifid_tree.heading("sig", text="IF/ID")
        self.ifid_tree.heading("val", text="Valor")
        self.ifid_tree.column("sig", width=120, anchor="w")
        self.ifid_tree.column("val", width=320, anchor="w")
        self.ifid_tree.grid(row=0, column=0, sticky="nsew", padx=(0,10), pady=(0,10))

        # ID/EX
        self.idex_tree = ttk.Treeview(pipe_tables, columns=("sig","val"), show="headings", height=8)
        self.idex_tree.heading("sig", text="ID/EX")
        self.idex_tree.heading("val", text="Valor")
        self.idex_tree.column("sig", width=120, anchor="w")
        self.idex_tree.column("val", width=320, anchor="w")
        self.idex_tree.grid(row=0, column=1, sticky="nsew", padx=(0,0), pady=(0,10))

        # EX/MEM
        self.exmem_tree = ttk.Treeview(pipe_tables, columns=("sig","val"), show="headings", height=7)
        self.exmem_tree.heading("sig", text="EX/MEM")
        self.exmem_tree.heading("val", text="Valor")
        self.exmem_tree.column("sig", width=120, anchor="w")
        self.exmem_tree.column("val", width=320, anchor="w")
        self.exmem_tree.grid(row=1, column=0, sticky="nsew", padx=(0,10), pady=(0,0))

        # MEM/WB
        self.memwb_tree = ttk.Treeview(pipe_tables, columns=("sig","val"), show="headings", height=6)
        self.memwb_tree.heading("sig", text="MEM/WB")
        self.memwb_tree.heading("val", text="Valor")
        self.memwb_tree.column("sig", width=120, anchor="w")
        self.memwb_tree.column("val", width=320, anchor="w")
        self.memwb_tree.grid(row=1, column=1, sticky="nsew", padx=(0,0), pady=(0,0))

        pipe_tables.columnconfigure(0, weight=1)
        pipe_tables.columnconfigure(1, weight=1)
        pipe_tables.rowconfigure(0, weight=1)
        pipe_tables.rowconfigure(1, weight=1)

        for tree in [self.ifid_tree, self.idex_tree, self.exmem_tree, self.memwb_tree]:
            tree.insert("", "end", values=("—", "—"))

        # Memory hexdump
        mem = ttk.LabelFrame(right, text="dmem[0..]", padding=10)
        mem.pack(fill="both", expand=True)

        self.mem_text = tk.Text(mem, height=18, width=45, font=("Consolas", 10))
        self.mem_text.pack(fill="both", expand=True)

        # Log
        log = ttk.LabelFrame(right, text="Log", padding=10)
        log.pack(fill="both", expand=True, pady=(10,0))

        self.log_text = tk.Text(log, height=10, font=("Consolas", 9))
        self.log_text.pack(fill="both", expand=True)

    def _refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_cb["values"] = ports
        if ports and not self.port_cb.get():
            self.port_cb.set(ports[0])

    def log(self, msg: str):
        self.log_text.insert("end", msg + "\n")
        self.log_text.see("end")

    def set_controls(self, connected: bool):
        state_on  = "normal" if connected else "disabled"
        state_off = "disabled" if connected else "normal"

        self.btn_connect.config(state=state_off)
        self.btn_disconnect.config(state=state_on)

        for b in [self.btn_dump, self.btn_step, self.btn_run, self.btn_rst, self.btn_prog, self.btn_progseq, self.btn_load]:
            b.config(state=state_on)

    # ---------------- Connect / Disconnect ----------------
    def connect(self):
        if self.host is not None:
            return
        port = self.port_cb.get().strip()
        if not port:
            messagebox.showerror("Error", "Elegí un puerto.")
            return
        try:
            baud = int(self.baud_var.get())
            dm = int(self.dm_var.get())
        except ValueError:
            messagebox.showerror("Error", "Baud y DM bytes deben ser números.")
            return

        try:
            self.host = DebugHost(port, baud, dm_dump_bytes=dm)
            self.set_controls(True)
            self.log(f"[INFO] Conectado a {port} @ {baud}, DM={dm}, PIPE_WORDS={PIPE_WORDS}")
        except Exception as e:
            self.host = None
            messagebox.showerror("Error", f"No pude conectar: {e}")

    def disconnect(self):
        if self.host is None:
            return
        try:
            self.host.close()
        finally:
            self.host = None
            self.set_controls(False)
            self.log("[INFO] Desconectado")

    def on_close(self):
        self.disconnect()
        self.destroy()

    # ---------------- Program loader ----------------
    def load_program_dialog(self):
        if self.host is None:
            return

        path = filedialog.askopenfilename(
            title="Seleccionar programa (.mem/.hex)",
            filetypes=[
                ("Mem/Hex", "*.mem *.hex *.txt"),
                ("Todos", "*.*")
            ]
        )
        if not path:
            return

        self.run_load_program(path)

    def run_load_program(self, path: str):
        def worker():
            with self.worker_lock:
                try:
                    items = parse_program_file(path)
                    if not items:
                        raise ValueError("El archivo no tiene words parseables.")

                    self.log(f"[INFO] Cargando programa: {path}")
                    self.log(f"[INFO] Words a programar: {len(items)}")

                    for k, (addr, word) in enumerate(items):
                        self.host.program_word(addr, word)
                        if (k+1) % 64 == 0:
                            self.log(f"[INFO] ... {k+1}/{len(items)}")

                    first_addr = items[0][0]
                    last_addr  = items[-1][0]
                    self.log(f"[OK] Programa cargado. Rango: 0x{first_addr:08x} .. 0x{last_addr:08x}")

                except Exception as e:
                    self.after(0, lambda: messagebox.showerror("Error", str(e)))
                    self.log(f"[ERR] {e}")

        threading.Thread(target=worker, daemon=True).start()

    # ---------------- Actions (threaded) ----------------
    def run_action(self, action: str):
        if self.host is None:
            return

        def worker():
            with self.worker_lock:
                try:
                    if action == "dump":
                        self.log("[TX] D (dump)")
                        self.host.send_cmd("D")
                        d = self.host.wait_dump(timeout_s=5.0)
                        self.after(0, lambda: self.apply_dump(d))

                    elif action == "step":
                        self.log("[TX] S (step)")
                        self.host.send_cmd("S")
                        d = self.host.wait_dump(timeout_s=8.0)
                        self.after(0, lambda: self.apply_dump(d))

                    elif action == "run":
                        self.log("[TX] G (run)")
                        self.host.send_cmd("G")
                        d = self.host.wait_dump(timeout_s=12.0)
                        self.after(0, lambda: self.apply_dump(d))

                    elif action == "reset":
                        self.log("[TX] R (reset fetch)")
                        self.host.send_cmd("R")

                    elif action == "prog":
                        addr = int(self.addr_var.get(), 0)
                        data = int(self.data_var.get(), 0)
                        self.log(f"[TX] P addr=0x{addr:08x} data=0x{data:08x}")
                        self.host.program_word(addr, data)

                    elif action == "progseq":
                        base = int(self.addr_var.get(), 0)
                        words_s = self.seq_var.get().strip()
                        if not words_s:
                            raise ValueError("Secuencia vacía")
                        words = [int(tok, 0) for tok in words_s.split()]
                        self.log(f"[TX] P(seq) base=0x{base:08x} n={len(words)}")
                        for i, w in enumerate(words):
                            self.host.program_word(base + 4*i, w)

                except Exception as e:
                    self.after(0, lambda: messagebox.showerror("Error", str(e)))
                    self.log(f"[ERR] {e}")

        threading.Thread(target=worker, daemon=True).start()

    # ---------------- Apply dump to UI ----------------
    def _set_tree_rows(self, tree: ttk.Treeview, rows: list[tuple[str,str]]):
        tree.delete(*tree.get_children())
        for k, v in rows:
            tree.insert("", "end", values=(k, v))

    def apply_dump(self, d: dict):
        t = dump_type_str(d["dump_type"])
        flags = d["flags"]
        pe = d["pipe_empty"]
        hs = d["halt_seen"]
        pc = d["pc"]
        pad = d["pad"]

        self.status_var.set(
            f"type={t}  flags=0x{flags:02x} (pipe_empty={pe} halt_seen={hs})  pc=0x{pc:08x}  pad=0x{pad:02x}"
        )
        self.log(f"[RX] DUMP type={t} flags=0x{flags:02x} pc=0x{pc:08x}")

        # Regs
        regs = d["regs"]
        for i, item in enumerate(self.reg_tree.get_children()):
            val = regs[i] & 0xFFFFFFFF
            sval = _signed32(val)
            self.reg_tree.item(item, values=(f"x{i}", f"0x{val:08x}", f"{sval}"))

        # Mem
        self.mem_text.delete("1.0", "end")
        for line in hexdump_lines(d["mem"], base=0):
            self.mem_text.insert("end", line + "\n")

        # Pipe
        pd = d.get("pipe_decoded", {})
        if "error" in pd:
            self.pipe_status_var.set(f"[PIPE] ERROR: {pd['error']}")
            return

        ifid = pd["ifid"]
        idex = pd["idex"]
        exmem = pd["exmem"]
        memwb = pd["memwb"]

        self.pipe_status_var.set(
            f"[PIPE] IF/ID v={ifid['valid']} | ID/EX v={idex['ctrl']['valid']} | EX/MEM v={exmem['ctrl']['valid']} | MEM/WB v={memwb['ctrl']['valid']}"
        )

        self._set_tree_rows(self.ifid_tree, [
            ("valid", str(ifid["valid"])),
            ("pc",    f"0x{ifid['pc']:08x}"),
            ("pc+4",  f"0x{ifid['pc4']:08x}"),
            ("instr", f"0x{ifid['instr']:08x}"),
        ])

        idex_ctrl = idex["ctrl"]
        self._set_tree_rows(self.idex_tree, [
            ("valid",      str(idex_ctrl["valid"])),
            ("pc",         f"0x{idex['pc']:08x}"),
            ("pc+4",       f"0x{idex['pc4']:08x}"),
            ("rs1_data",   f"0x{idex['rs1_data']:08x} ({_signed32(idex['rs1_data'])})"),
            ("rs2_data",   f"0x{idex['rs2_data']:08x} ({_signed32(idex['rs2_data'])})"),
            ("imm",        f"0x{idex['imm']:08x} ({_signed32(idex['imm'])})"),
            ("rs1/rs2/rd", f"{idex['rs1']}/{idex['rs2']}/{idex['rd']}"),
            ("f3/f7",      f"{idex['funct3']}/{idex['funct7']}"),
            ("ctrl",       f"RW={idex_ctrl['reg_write']} MR={idex_ctrl['mem_read']} MW={idex_ctrl['mem_write']} "
                           f"M2R={idex_ctrl['mem_to_reg']} AS={idex_ctrl['alu_src']} "
                           f"ALUop={idex_ctrl['alu_op']} BR={idex_ctrl['branch']} J={idex_ctrl['jump']} JALR={idex_ctrl['jalr']} PC4={idex_ctrl['wb_sel_pc4']}"),
        ])

        exmem_ctrl = exmem["ctrl"]
        self._set_tree_rows(self.exmem_tree, [
            ("valid",        str(exmem_ctrl["valid"])),
            ("alu_result",   f"0x{exmem['alu_result']:08x} ({_signed32(exmem['alu_result'])})"),
            ("rs2_pass",     f"0x{exmem['rs2_pass']:08x} ({_signed32(exmem['rs2_pass'])})"),
            ("br_target",    f"0x{exmem['branch_target']:08x}"),
            ("pc+4",         f"0x{exmem['pc4']:08x}"),
            ("rd/f3",        f"{exmem['rd']}/{exmem['funct3']}"),
            ("ctrl",         f"RW={exmem_ctrl['reg_write']} MR={exmem_ctrl['mem_read']} MW={exmem_ctrl['mem_write']} "
                             f"M2R={exmem_ctrl['mem_to_reg']} BT={exmem_ctrl['branch_taken']} PC4={exmem_ctrl['wb_sel_pc4']}"),
        ])

        memwb_ctrl = memwb["ctrl"]
        self._set_tree_rows(self.memwb_tree, [
            ("valid",        str(memwb_ctrl["valid"])),
            ("mem_data",     f"0x{memwb['mem_read_data']:08x} ({_signed32(memwb['mem_read_data'])})"),
            ("alu_result",   f"0x{memwb['alu_result']:08x} ({_signed32(memwb['alu_result'])})"),
            ("pc+4",         f"0x{memwb['pc4']:08x}"),
            ("rd",           f"{memwb['rd']}"),
            ("ctrl",         f"RW={memwb_ctrl['reg_write']} M2R={memwb_ctrl['mem_to_reg']} PC4={memwb_ctrl['wb_sel_pc4']}"),
        ])

def main():
    app = App()
    app.mainloop()

if __name__ == "__main__":
    main()
