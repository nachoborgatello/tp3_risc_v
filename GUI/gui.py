import struct
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

import serial
import serial.tools.list_ports

MAGIC = 0xD0

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
    """
    items: list[tuple[int, int]] = []
    base = 0  # addr byte actual
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            s = _strip_comment(raw)
            if not s:
                continue

            # Marcador de dirección: @ADDR
            if s.startswith("@"):
                addr_s = s[1:].strip()
                base = int(addr_s, 16) if addr_s.lower().startswith("0x") is False else int(addr_s, 0)
                # si te pasan en words y querés bytes, descomentá:
                # base = base * 4
                continue

            # También permito "ADDR:DATA"
            if ":" in s:
                a_s, d_s = s.split(":", 1)
                a_s = a_s.strip()
                d_s = d_s.strip()
                addr = int(a_s, 0) if a_s.lower().startswith("0x") else int(a_s, 16)
                word = int(d_s, 0) if d_s.lower().startswith("0x") else int(d_s, 16)
                items.append((addr & 0xFFFFFFFF, word & 0xFFFFFFFF))
                continue

            # Caso normal: word suelta => va en base, base+=4
            word = int(s, 0) if s.lower().startswith("0x") else int(s, 16)
            items.append((base & 0xFFFFFFFF, word & 0xFFFFFFFF))
            base = (base + 4) & 0xFFFFFFFF

    return items

class DebugHost:
    def __init__(self, port: str, baud: int, dm_dump_bytes: int = 64, timeout_s: float = 0.2):
        self.dm_dump_bytes = dm_dump_bytes
        self.frame_len = 4 + 4 + 32*4 + dm_dump_bytes
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

        regs = list(struct.unpack_from("<32I", frame, off))
        off += 32*4

        mem = frame[off:off + self.dm_dump_bytes]

        return {
            "dump_type": dump_type,
            "flags": flags,
            "pipe_empty": pipe_empty,
            "halt_seen": halt_seen,
            "pad": pad,
            "pc": pc,
            "regs": regs,
            "mem": mem
        }

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("RISC-V Debug Host (UART) - Basys3")
        self.geometry("1120x740")

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

        # Registers table
        regs = ttk.LabelFrame(left, text="Registros x0..x31", padding=10)
        regs.pack(fill="both", expand=True, pady=(10,0))

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
            self.log(f"[INFO] Conectado a {port} @ {baud}, DM={dm}")
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

        # Por defecto, respetamos las direcciones del archivo si trae @ADDR o ADDR:DATA.
        # Si el archivo es secuencial sin @, empieza en 0.
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

                    # Programar (addr,data) uno por uno
                    # Nota: tu debug_unit hace imem_dbg_we pulso 1 ciclo, alcanza con enviar la secuencia.
                    for k, (addr, word) in enumerate(items):
                        self.host.program_word(addr, word)
                        # pequeño respiro opcional si tu UART/CPU es muy sensible
                        # time.sleep(0.0005)

                        if (k+1) % 64 == 0:
                            self.log(f"[INFO] ... {k+1}/{len(items)}")

                    first_addr = items[0][0]
                    last_addr  = items[-1][0]
                    self.log(f"[OK] Programa cargado. Rango: 0x{first_addr:08x} .. 0x{last_addr:08x}")

                    # opcional: reset fetch automático
                    # self.host.send_cmd("R")
                    # self.log("[TX] R (reset fetch)")

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

        regs = d["regs"]
        for i, item in enumerate(self.reg_tree.get_children()):
            val = regs[i] & 0xFFFFFFFF
            sval = val if val < 0x80000000 else val - 0x100000000
            self.reg_tree.item(item, values=(f"x{i}", f"0x{val:08x}", f"{sval}"))

        self.mem_text.delete("1.0", "end")
        for line in hexdump_lines(d["mem"], base=0):
            self.mem_text.insert("end", line + "\n")

def main():
    app = App()
    app.mainloop()

if __name__ == "__main__":
    main()
