#!/usr/bin/env python3
"""
Team MAHINA - EDL flight computer (Raspberry Pi, or any laptop in --mock mode)

What it does (maps to the ASTE577 flight-computer demo checklist):
  * Integrates the same 3-DOF entry equations as matlab/src/edl_dynamics.m in real time
    (TIME_SCALE speeds the 11-min descent up so it fits in a 15-min talk).
  * Fires every phase from altitude / Mach triggers and prints + logs a telemetry message
    for each major event (entry, peak heating, peak decel, drogue, separation, terminal, landing).
  * Drives LEDs per event and a pulsing "T-10 s to landing" countdown LED.
  * Reads a temperature sensor (DS18B20); an over-temp / rapid-rise triggers a FAULT that is
    latched, flagged in the telemetry stream and answered with a fault response.
  * Logs accelerometer (MPU-6050) data from start of terminal descent until after landing
    (drop the Pi when it prints "START OF TERMINAL DESCENT").
  * Sends a landing message by email/SMS-gateway (SMTP credentials via environment variables).

Run:   python3 edl_flight_computer.py --mock --scale 30 --inject-fault-at 250
Pi:    python3 edl_flight_computer.py --scale 10
"""
import argparse, csv, glob, json, math, os, smtplib, sys, threading, time
from datetime import datetime
from email.message import EmailMessage

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------- hardware
PINS = dict(entry=17, peak_heat=27, peak_decel=22, chute=23, separation=24,
            terminal=25, landing=5, countdown=6, fault=16)      # BCM numbering

try:
    from gpiozero import LED, PWMLED
    HAVE_GPIO = True
except Exception:                                   # laptop / no gpiozero
    HAVE_GPIO = False

class MockLED:
    def __init__(self, name): self.name = name
    def on(self):  print(f"      [LED {self.name:<10} ON ]")
    def off(self): print(f"      [LED {self.name:<10} OFF]")
    def pulse(self, *a, **k): print(f"      [LED {self.name:<10} PULSING]")
    def blink(self, *a, **k): print(f"      [LED {self.name:<10} BLINKING]")

def make_leds(mock):
    if mock or not HAVE_GPIO:
        return {k: MockLED(k) for k in PINS}
    return {k: (PWMLED(p) if k == "countdown" else LED(p)) for k, p in PINS.items()}

class TempSensor:
    """DS18B20 on 1-Wire (enable with: sudo raspi-config -> Interfaces -> 1-Wire; data pin GPIO4)."""
    def __init__(self, mock, inject_at=None):
        self.mock, self.inject_at, self.sim_t = mock, inject_at, 0.0
        self.path = None
        if not mock:
            dev = glob.glob("/sys/bus/w1/devices/28-*/w1_slave")
            if not dev: sys.exit("No DS18B20 found. Check wiring/1-Wire, or run with --mock.")
            self.path = dev[0]
    def read_c(self):
        if self.mock:
            hot = self.inject_at is not None and self.sim_t >= self.inject_at
            return 22.0 + (25.0 if hot else 0.0) + 0.1 * math.sin(self.sim_t)
        with open(self.path) as f:
            lines = f.read().splitlines()
        return int(lines[1].split("t=")[1]) / 1000.0

class Accelerometer:
    """MPU-6050 on I2C (address 0x68, +/-16 g range). Needs: pip install smbus2"""
    def __init__(self, mock):
        self.mock = mock
        if not mock:
            import smbus2
            self.bus = smbus2.SMBus(1)
            self.bus.write_byte_data(0x68, 0x6B, 0x00)     # wake
            self.bus.write_byte_data(0x68, 0x1C, 0x18)     # +/-16 g -> 2048 LSB/g
    def read_g(self):
        if self.mock:
            return (0.02, -0.01, 1.0 + 0.02 * math.sin(time.time() * 20))
        d = self.bus.read_i2c_block_data(0x68, 0x3B, 6)
        v = [(d[i] << 8 | d[i + 1]) for i in (0, 2, 4)]
        return tuple((x - 65536 if x > 32767 else x) / 2048.0 for x in v)

class AccelLogger(threading.Thread):
    def __init__(self, acc, path, hz=100):
        super().__init__(daemon=True)
        self.acc, self.path, self.dt, self.stop_flag = acc, path, 1.0 / hz, threading.Event()
    def run(self):
        with open(self.path, "w", newline="") as f:
            w = csv.writer(f); w.writerow(["wall_time_s", "ax_g", "ay_g", "az_g"])
            t0 = time.monotonic()
            while not self.stop_flag.is_set():
                w.writerow([f"{time.monotonic() - t0:.3f}", *[f"{a:.3f}" for a in self.acc.read_g()]])
                time.sleep(self.dt)

def send_landing_message(text):
    """Email (or carrier SMS gateway, e.g. 5551234567@vtext.com). Set SMTP_USER, SMTP_PASS, NOTIFY_TO."""
    user, pw, to = (os.getenv(k) for k in ("SMTP_USER", "SMTP_PASS", "NOTIFY_TO"))
    if not (user and pw and to):
        print(f"      [MOCK MESSAGE -> no SMTP env vars set] {text}")
        return
    def _send():
        try:
            m = EmailMessage(); m["From"], m["To"], m["Subject"] = user, to, "MAHINA landed"
            m.set_content(text)
            with smtplib.SMTP_SSL("smtp.gmail.com", 465, timeout=20) as s:
                s.login(user, pw); s.send_message(m)
            print("      [MESSAGE SENT]")
        except Exception as e:                              # never let comms crash the flight computer
            print(f"      [MESSAGE FAILED: {e}]")
    threading.Thread(target=_send, daemon=True).start()

# ----------------------------------------------------------------------------- physics
_HK = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 150]
_RHO = [1.225, 0.4135, 0.0889, 0.0184, 3.996e-3, 1.027e-3, 3.097e-4, 8.283e-5, 1.846e-5,
        3.416e-6, 5.604e-7, 9.708e-8, 2.222e-8, 8.152e-9, 2.076e-9]
_T = [288.15, 223.25, 216.65, 226.51, 250.35, 270.65, 247.02, 219.58, 198.64, 186.87,
      195.08, 240, 360, 469.3, 634]
_LR = [math.log(r) for r in _RHO]

def _interp(x, xs, ys):
    x = min(max(x, xs[0]), xs[-1])
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            f = (x - xs[i]) / (xs[i + 1] - xs[i]); return ys[i] + f * (ys[i + 1] - ys[i])
    return ys[-1]

def atmosphere(h):
    hk = h / 1e3
    return math.exp(_interp(hk, _HK, _LR)), math.sqrt(1.4 * 287.053 * _interp(hk, _HK, _T))

class Vehicle:
    def __init__(self, cfg):
        self.c, self.phase = cfg, "ENTRY"
        self.y = [cfg["entry"]["h0"], cfg["entry"]["v0"], math.radians(cfg["entry"]["gamma0_deg"]), 0.0]
        self.set_phase("ENTRY")
    def set_phase(self, phase):
        c, v = self.c, self.c["veh"]; self.phase = phase
        sub = v["Cd_sub"] * v["area"]
        if phase == "ENTRY":   self.mass, self.CdA, self.LD, self.bank = v["mass"], v["Cd"] * v["area"], v["LD"], v["bank_deg"]
        elif phase == "DROGUE": self.mass, self.CdA, self.LD, self.bank = v["mass"], sub + c["chute"]["CdA_drogue"], 0, 0
        else:                   self.mass, self.CdA, self.LD, self.bank = v["mass"] - v["shield_m"], sub + c["chute"]["CdA_main"], 0, 0
    def _f(self, y):
        c = self.c; h, v, g, x = y; r = c["Re"] + h
        rho, _ = atmosphere(h); gr = c["mu"] / r ** 2
        dr = 0.5 * rho * v * v * self.CdA / self.mass
        lf = self.LD * dr * math.cos(math.radians(self.bank))
        return [v * math.sin(g), -dr - gr * math.sin(g), lf / v + (v / r - gr / v) * math.cos(g),
                v * math.cos(g) * c["Re"] / r]
    def step(self, dt):
        y = self.y; f = self._f
        k1 = f(y); k2 = f([a + dt / 2 * b for a, b in zip(y, k1)])
        k3 = f([a + dt / 2 * b for a, b in zip(y, k2)]); k4 = f([a + dt * b for a, b in zip(y, k3)])
        self.y = [a + dt / 6 * (b + 2 * c_ + 2 * d + e) for a, b, c_, d, e in zip(y, k1, k2, k3, k4)]
    def derived(self):
        c = self.c; h, v, g, _ = self.y; rho, a = atmosphere(h)
        q = 0.5 * rho * v * v; dr = q * self.CdA / self.mass
        accel_g = dr * math.sqrt(1 + (self.LD * math.cos(math.radians(self.bank))) ** 2) / c["g0"]
        qdot = c["heat"]["k_sg"] * math.sqrt(rho / c["veh"]["Rn"]) * v ** 3 / 1e4 if self.phase == "ENTRY" else 0.0
        return dict(h=h, v=v, mach=v / a, accel_g=accel_g, qdot=qdot, vdown=-v * math.sin(g))

# ----------------------------------------------------------------------------- flight software
class FlightComputer:
    TEMP_LIMIT_C, TEMP_RISE_C = 35.0, 8.0

    def __init__(self, cfg, args):
        self.cfg, self.args = cfg, args
        self.leds = make_leds(args.mock)
        self.temp = TempSensor(args.mock, args.inject_fault_at)
        self.acc = Accelerometer(args.mock)
        self.veh = Vehicle(cfg)
        self.t = 0.0; self.seq = 0; self.fault = None; self.baseline = None
        self.peak_q = self.peak_g = 0.0; self.done = set(); self.logger = None
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        os.makedirs(os.path.join(HERE, "..", "data"), exist_ok=True)
        self.tlm_path = os.path.join(HERE, "..", "data", f"telemetry_{stamp}.csv")
        self.acc_path = os.path.join(HERE, "..", "data", f"accel_{stamp}.csv")
        self.tlm_file = open(self.tlm_path, "w", newline=""); self.tlm = csv.writer(self.tlm_file)
        self.tlm.writerow(["seq", "t_s", "phase", "h_m", "v_mps", "mach", "g", "qdot_Wcm2", "temp_C", "fault"])
        self.last_cd, self.last_tlm = None, -1e9

    # --- messages -----------------------------------------------------------------
    def event(self, name, led=None, hold_s=2.0):
        d = self.veh.derived()
        print(f"[T+{self.t:7.1f}s | h {d['h']/1e3:7.2f} km | v {d['v']:7.1f} m/s | M {d['mach']:5.2f}] EVENT: {name}")
        if led:
            self.leds[led].on()
            if led != "landing": threading.Timer(hold_s, self.leds[led].off).start()

    def frame(self, d, temp):
        """Telemetry packet, NMEA-style checksum:  $EDL,seq,t,phase,h,v,mach,g,qdot,temp,fault*CS"""
        body = (f"EDL,{self.seq},{self.t:.1f},{self.veh.phase},{d['h']:.0f},{d['v']:.1f},"
                f"{d['mach']:.2f},{d['accel_g']:.2f},{d['qdot']:.0f},{temp:.1f},{self.fault or 'OK'}")
        cs = 0
        for ch in body: cs ^= ord(ch)
        return f"${body}*{cs:02X}"

    # --- fault management ---------------------------------------------------------
    def check_fault(self, temp):
        if self.baseline is None: self.baseline = temp
        tripped = temp > self.TEMP_LIMIT_C or temp - self.baseline > self.TEMP_RISE_C
        if tripped and not self.fault:
            self.fault = "OVERTEMP"
            self.event(f"*** FAULT: OVER-TEMPERATURE ({temp:.1f} C) -> SAFE-MODE, TLM RATE x4, FAULT FLAG SET ***")
            self.leds["fault"].on()                      # latched until fault clears
        elif self.fault and temp < self.TEMP_LIMIT_C - 2 and temp - self.baseline < self.TEMP_RISE_C - 2:
            self.event("FAULT CLEARED"); self.fault = None; self.leds["fault"].off()

    # --- phase logic (triggers) --------------------------------------------------------
    def phase_logic(self, d):
        c = self.cfg
        if "entry" not in self.done:
            self.done.add("entry"); self.event("ATMOSPHERIC ENTRY (122 km)", "entry", 3)
        self.peak_q, self.peak_g = max(self.peak_q, d["qdot"]), max(self.peak_g, d["accel_g"])
        if "heat" not in self.done and self.peak_q > 50 and d["qdot"] < 0.95 * self.peak_q:
            self.done.add("heat"); self.event(f"PEAK HEATING (~{self.peak_q:.0f} W/cm^2, detected on the way down)", "peak_heat")
        if "decel" not in self.done and self.peak_g > 2 and d["accel_g"] < 0.95 * self.peak_g:
            self.done.add("decel"); self.event(f"PEAK DECELERATION (~{self.peak_g:.1f} g, detected on the way down)", "peak_decel")
        if self.veh.phase == "ENTRY" and d["mach"] <= c["chute"]["mach_drogue"]:
            self.veh.set_phase("DROGUE"); self.event(f"DROGUE PARACHUTE DEPLOY (Mach {d['mach']:.2f})", "chute")
        elif self.veh.phase == "DROGUE" and d["h"] <= c["land"]["h"] + c["chute"]["h_main_agl"]:
            self.veh.set_phase("MAIN")
            self.event("MAIN PARACHUTE DEPLOY", "chute")
            self.event("HEAT SHIELD SEPARATION", "separation")
            self.event("START OF TERMINAL DESCENT  >>> RELEASE THE LANDER NOW <<<", "terminal", 5)
            self.logger = AccelLogger(self.acc, self.acc_path); self.logger.start()
        if self.veh.phase == "MAIN":                      # T-10 s landing counter (wall-clock seconds)
            vref = max(d["vdown"], c["chute"]["v_land_target"])   # estimate: never faster than current speed
            ttg_wall = (d["h"] - c["land"]["h"]) / vref / self.args.scale
            if ttg_wall <= 10:
                n = max(int(math.ceil(ttg_wall)), 0)
                if self.last_cd is None: self.leds["countdown"].pulse(0.5, 0.5)
                if self.last_cd is None or n < self.last_cd:   # counter only counts down
                    print(f"      LANDING IN {n:2d} s"); self.last_cd = n
        return d["h"] <= c["land"]["h"]

    # --- main loop -----------------------------------------------------------------
    def run(self):
        print(f"MAHINA EDL FLIGHT COMPUTER | scale x{self.args.scale} | mock={self.args.mock or not HAVE_GPIO}")
        wall_dt, nxt = 0.05, time.monotonic()
        landed = False
        while True:
            dt_sim = wall_dt * self.args.scale
            if not landed:
                for _ in range(max(1, math.ceil(dt_sim / 0.25))):
                    self.veh.step(dt_sim / max(1, math.ceil(dt_sim / 0.25)))
                self.t += dt_sim; self.temp.sim_t = self.t
                d = self.veh.derived(); temp = self.temp.read_c()
                self.check_fault(temp)
                landed = self.phase_logic(d)
                rate = 0.25 if self.fault else 1.0           # fault response: 4x telemetry rate
                if self.t - self.last_tlm >= rate * self.args.scale:
                    self.last_tlm = self.t; self.seq += 1
                    print(self.frame(d, temp))
                    self.tlm.writerow([self.seq, f"{self.t:.1f}", self.veh.phase, f"{d['h']:.0f}", f"{d['v']:.1f}",
                                       f"{d['mach']:.2f}", f"{d['accel_g']:.2f}", f"{d['qdot']:.0f}", f"{temp:.1f}", self.fault or "OK"])
                if landed:
                    self.event("LANDING - TOUCHDOWN", "landing")
                    self.leds["countdown"].off()
                    send_landing_message(f"MAHINA has landed at T+{self.t:.0f}s, v={d['v']:.1f} m/s. All EDL events nominal"
                                         f"{'' if not self.fault else ' (fault flagged: ' + self.fault + ')'}.")
                    land_wall = time.monotonic()
            elif time.monotonic() - land_wall > self.args.post_landing:
                break
            nxt += wall_dt; time.sleep(max(0.0, nxt - time.monotonic()))
        if self.logger: self.logger.stop_flag.set(); self.logger.join(timeout=2)
        self.tlm_file.close()
        print(f"Done. Telemetry -> {os.path.relpath(self.tlm_path)}   Accel -> {os.path.relpath(self.acc_path)}")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=os.path.join(HERE, "mission_config.json"))
    ap.add_argument("--scale", type=float, default=10.0, help="sim seconds per wall second (default 10)")
    ap.add_argument("--mock", action="store_true", help="no GPIO / sensors (laptop development)")
    ap.add_argument("--inject-fault-at", type=float, default=None, help="[mock] sim time (s) to inject over-temp")
    ap.add_argument("--post-landing", type=float, default=30.0, help="wall seconds to keep logging after landing")
    args = ap.parse_args()
    with open(args.config) as f: cfg = json.load(f)
    FlightComputer(cfg, args).run()

if __name__ == "__main__":
    main()
