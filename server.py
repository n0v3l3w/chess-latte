import os
import sys
import psutil
import subprocess
import threading
import time
import tkinter as tk
from tkinter import filedialog

from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse
import uvicorn
import chess


class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    YELLOW_BOLD = '\033[1;33m'
    RESET = '\033[0m'


def print_color(text, color, end="\n"):
    print(f"{color}{text}{Colors.RESET}", end=end)


class Engine:

    LC0_NODES_MULTIPLIER = 1000

    def __init__(self, engine_path):
        self.path = engine_path
        self.movetime = 100
        self.is_lc0 = False
        self.engine_name = "Unknown"
        self.engine_proc = None
        self._lock = threading.Lock()

        try:
            self.engine_proc = subprocess.Popen(
                self.path,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
        except Exception as err:
            raise Exception(f"Failed to start engine subprocess: {err}")

        self.send_cmd("uci")
        output = self._read_until("uciok")

        if "uciok" not in output:
            raise Exception("Selected executable doesn't look like a UCI engine.")

        for line in output.splitlines():
            if line.startswith("id name"):
                self.engine_name = line[len("id name"):].strip()
                name_lower = self.engine_name.lower()
                if "lc0" in name_lower or "leela" in name_lower or "lczero" in name_lower:
                    self.is_lc0 = True
                break

    def send_cmd(self, command):
        with self._lock:
            if self.engine_proc and self.engine_proc.stdin:
                self.engine_proc.stdin.write(command.strip() + "\n")
                self.engine_proc.stdin.flush()

    def _read_line(self):
        if not self.engine_proc or not self.engine_proc.stdout:
            return ""
        return self.engine_proc.stdout.readline()

    def _read_until(self, prefix):
        lines = []
        while True:
            line = self._read_line()
            lines.append(line)
            if line.startswith(prefix):
                break
        return "".join(lines)

    def set_option(self, name, value):
        self.send_cmd(f"setoption name {name} value {value}")
        self.send_cmd("isready")
        self._read_until("readyok")

    def set_position(self, fen):
        self.send_cmd(f"position fen {fen}")

    def get_best_move(self, depth, ignore_time, nodes=0):
        if self.is_lc0:
            effective_nodes = nodes if nodes > 0 else depth * self.LC0_NODES_MULTIPLIER
            if ignore_time:
                cmd = f"go nodes {effective_nodes}"
            else:
                cmd = f"go nodes {effective_nodes} movetime {self.movetime}"
        else:
            if ignore_time:
                cmd = f"go depth {depth}"
            else:
                cmd = f"go depth {depth} movetime {self.movetime}"

        self.send_cmd(cmd)

        while True:
            line = self._read_line()
            if line.startswith("bestmove"):
                parts = line.strip().split()
                if len(parts) >= 2:
                    return parts[1]
                return ""


def get_int_input(prompt, allow_empty):
    while True:
        print()
        raw = input(prompt + "\n> ").strip()

        if allow_empty and raw == "":
            return None

        try:
            return int(raw)
        except ValueError:
            print_color("Invalid number. Try again.", Colors.RED)


def choose_engine_settings(is_lc0=False):
    print_color("Leave these empty if you aren't sure what they do!", Colors.RED)

    mem = psutil.virtual_memory()

    total_gb = mem.total / (1024 ** 3)
    total_mb = mem.total / (1024 ** 2)
    free_gb = mem.available / (1024 ** 3)
    free_mb = mem.available / (1024 ** 2)

    if is_lc0:
        cache_prompt = (
            f"Enter NNCacheSize (number of cache entries, e.g. 200000)\n"
            f"RAM Total: {int(total_gb)} GB | Free: {int(free_gb)} GB\n"
            f"Higher = more RAM used. Leave empty to skip."
        )
        hash_val = get_int_input(cache_prompt, True)
    else:
        hash_prompt = (
            f"Enter hash amount in MB\n"
            f"Total: {int(total_gb)} GB | {int(total_mb):,} MB\n"
            f"Free: {int(free_gb)} GB | {int(free_mb):,} MB"
        )
        hash_val = get_int_input(hash_prompt, True)

    cpu_total = psutil.cpu_count(logical=True)
    thread_prompt = f"Enter thread count\nTotal: {cpu_total}"
    threads_val = get_int_input(thread_prompt, True)

    syzygy_path = ""

    if not is_lc0:
        while True:
            print()
            ans = input("Do you have Syzygy tablebases? (y/n)\n> ").lower().strip()

            if ans == "" or ans == "n":
                break

            if ans == "y":
                root = tk.Tk()
                root.withdraw()

                folder = filedialog.askdirectory(title="Choose Syzygy folder")

                if folder:
                    syzygy_path = folder + ";"
                    break
                else:
                    print("No folder selected... try again maybe.")
            else:
                print_color("Please type y or n.", Colors.RED)

    return hash_val, threads_val, syzygy_path


def choose_engine_file():
    print("Choose engine executable (Stockfish or Lc0).")

    root = tk.Tk()
    root.withdraw()

    if sys.platform == "win32":
        types = [("Executable", "*.exe")]
    else:
        types = [("All Files", "*.*")]

    engine_path = filedialog.askopenfilename(
        title="Locate engine executable (Stockfish or Lc0)",
        filetypes=types
    )

    if not engine_path:
        print_color("You must select an engine executable.", Colors.RED)
        if sys.platform == "win32":
            os.system("pause")
        sys.exit(1)

    if sys.platform == "darwin":
        if not os.access(engine_path, os.X_OK):
            print_color("Selected file isn't executable.", Colors.RED)
            sys.exit(1)

    print_color("Engine selected successfully!\n", Colors.GREEN)
    return engine_path


app = FastAPI()
engine = None


@app.get("/api/info")
async def info():
    global engine
    return {
        "engine_name": engine.engine_name,
        "is_lc0": engine.is_lc0,
        "nodes_multiplier": engine.LC0_NODES_MULTIPLIER if engine.is_lc0 else None,
    }


@app.get("/api/solve")
async def solve(
    fen: str = Query(...),
    depth: int = Query(17),
    nodes: int = Query(0),
    max_think_time: int = Query(100),
    disregard_think_time: bool = Query(False)
):
    global engine

    print_color("FEN", Colors.MAGENTA, end="")
    print(f": {fen}")

    if engine.is_lc0:
        effective_nodes = nodes if nodes > 0 else depth * engine.LC0_NODES_MULTIPLIER
        print_color("Nodes", Colors.MAGENTA, end="")
        print(f": {effective_nodes}")
    else:
        print_color("Depth", Colors.MAGENTA, end="")
        print(f": {depth}")

    print_color("Max Think Time", Colors.MAGENTA, end="")
    print(f": {max_think_time}")

    print_color("Disregard Think Time", Colors.MAGENTA, end="")
    print(f": {disregard_think_time}")

    try:
        board = chess.Board(fen)
    except ValueError:
        print_color("Invalid FEN\n", Colors.RED)
        return JSONResponse(
            status_code=400,
            content={"success": False, "result": "Invalid FEN"}
        )

    start = time.time()

    try:
        engine.set_position(fen)
        engine.movetime = max_think_time
        best_move = engine.get_best_move(depth, disregard_think_time, nodes)
    except Exception as err:
        print_color(f"Engine error: {err}\n", Colors.RED)
        return JSONResponse(
            status_code=400,
            content={"success": False, "result": str(err)}
        )

    duration = time.time() - start

    print_color("Returned", Colors.MAGENTA, end="")
    print(f": {best_move}")

    print_color("Time Taken", Colors.MAGENTA, end="")
    print(f": {duration:.3f}s\n")

    return {"success": True, "result": best_move}


def choose_engine_settings(is_lc0=False):
    print_color("Leave these empty if you aren't sure what they do!", Colors.RED)

    mem = psutil.virtual_memory()
    total_gb = mem.total / (1024 ** 3)
    free_gb = mem.available / (1024 ** 3)

    weights_path = ""
    if is_lc0:
        while True:
            print()
            ans = input("Do you want to specify an Lc0 weights file (.pb.gz)? (y/n)\n> ").lower().strip()
            if ans == "n" or ans == "":
                break
            if ans == "y":
                root = tk.Tk()
                root.withdraw()
                file_path = filedialog.askopenfilename(
                    title="Select Lc0 Weights File",
                    filetypes=[("Weights File", "*.pb.gz"), ("All Files", "*.*")]
                )
                if file_path:
                    weights_path = file_path
                    break
                else:
                    print("No file selected... skipping.")
                    break
            else:
                print_color("Please type y or n.", Colors.RED)

    if is_lc0:
        cache_prompt = (
            f"Enter NNCacheSize (number of cache entries, e.g. 200000)\n"
            f"RAM Total: {int(total_gb)} GB | Free: {int(free_gb)} GB\n"
            f"Leave empty to skip."
        )
        hash_val = get_int_input(cache_prompt, True)
    else:
        hash_prompt = (
            f"Enter hash amount in MB\n"
            f"Total: {int(total_gb)} GB | Free: {int(free_gb)} GB"
        )
        hash_val = get_int_input(hash_prompt, True)

    cpu_total = psutil.cpu_count(logical=True)
    thread_prompt = f"Enter thread count\nTotal: {cpu_total}"
    threads_val = get_int_input(thread_prompt, True)

    syzygy_path = ""
    while True:
        print()
        ans = input("Do you have Syzygy tablebases? (y/n)\n> ").lower().strip()

        if ans == "" or ans == "n":
            break

        if ans == "y":
            root = tk.Tk()
            root.withdraw()
            folder = filedialog.askdirectory(title="Choose Syzygy folder")
            if folder:
                syzygy_path = folder if is_lc0 else folder + ";"
                break
            else:
                print("No folder selected... skipping.")
                break
        else:
            print_color("Please type y or n.", Colors.RED)

    return hash_val, threads_val, syzygy_path, weights_path


def main():
    global engine
    print_color("If something breaks, try updating first.", Colors.CYAN)

    engine_path = choose_engine_file()

    try:
        engine = Engine(engine_path)
    except Exception as err:
        print_color(f"\nCould not start engine: {err}\n", Colors.RED)
        if sys.platform == "win32": os.system("pause")
        sys.exit(1)

    if engine.is_lc0:
        print_color(f"Detected Lc0 engine: {engine.engine_name}", Colors.CYAN)
    else:
        print_color(f"Detected engine: {engine.engine_name}", Colors.CYAN)

    hash_val, threads_val, syzygy, weights_path = choose_engine_settings(engine.is_lc0)

    if weights_path:
        engine.set_option("WeightsFile", weights_path)

    if hash_val is not None:
        if engine.is_lc0:
            engine.set_option("NNCacheSize", str(hash_val))
        else:
            engine.set_option("Hash", str(hash_val))

    if threads_val is not None:
        engine.set_option("Threads", str(threads_val))

    if syzygy:
        engine.set_option("SyzygyPath", syzygy)

    engine.set_option("MultiPV", "1")

    print_color("\nServer started at http://localhost:3000\n", Colors.GREEN)
    uvicorn.run(app, host="127.0.0.1", port=3000, log_level="error")


if __name__ == "__main__":
    if sys.platform == "win32":
        os.system("color")
    main()
