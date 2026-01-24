import struct
import time
import serial

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

class DebugHost:
    """
    Host UART. Frame:
      4B header + 4B PC + PIPE_WORDS*4 + 32*4 regs + DM bytes
    """
    def __init__(self, port: str, baud: int, pipe_words: int, dm_dump_bytes: int = 64, timeout_s: float = 0.2):
        self.pipe_words = pipe_words
        self.dm_dump_bytes = dm_dump_bytes
        self.frame_len = 4 + 4 + pipe_words*4 + 32*4 + dm_dump_bytes

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

    def wait_dump(self, timeout_s: float = 5.0) -> bytes:
        deadline = time.time() + timeout_s
        sync_to_magic(self.ser, deadline)
        rest = read_exact(self.ser, self.frame_len - 1)
        return bytes([MAGIC]) + rest
