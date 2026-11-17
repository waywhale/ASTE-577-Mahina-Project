# Team MAHINA - EDL Term Project (ASTE 577)

Earth entry, descent and landing of the MAHINA lunar-sample-return **Ascender** (11 km/s, 7 deg entry,
PICA shield, drogue + main parachute, Utah dry-lake landing), plus the Raspberry Pi EDL flight-computer demo.

## Repo layout
| Folder | What lives here |
|---|---|
| `matlab/config/edl_params.m` | **Every assumption in one place.** Edit here, never inside other files. |
| `matlab/src/` | Model: atmosphere, equations of motion, chute sizing, heating, plots |
| `matlab/main_edl.m` | Run this. Prints the summary, saves plots + CSV, exports `flight_computer/mission_config.json` |
| `matlab/analysis/` | Trade studies (entry-angle sweep, lift/skip entry, TPS, structure sizing...) |
| `matlab/tests/` | Sanity tests - run before every PR |
| `flight_computer/` | Raspberry Pi code (`edl_flight_computer.py`) + generated `mission_config.json` |
| `hardware/` | Wiring diagram, BOM, photos of the demo rig |
| `spreadsheet/` | MEL/PEL working CSVs + the course spreadsheet template |
| `docs/` | `assumptions.md` (every number + reference), `GIT_WORKFLOW.md` |
| `report/` | Report drafts (one file per section) and slides |
| `data/` | Telemetry / accelerometer logs from demo runs |

## Quick start
```matlab
>> cd matlab
>> main_edl                       % run the sim + make the 4 required plots
>> runtests('tests/test_edl_sanity')   % (or run the file in VS Code)
```
```bash
cd flight_computer
python3 edl_flight_computer.py --mock --scale 30 --inject-fault-at 250   # laptop test
python3 edl_flight_computer.py --scale 10                                 # on the Pi
```
Needs MATLAB R2021b+ (for `jsonencode(...,'PrettyPrint')`). VS Code: install the recommended extensions
(popup on first open) and set `MATLAB.installPath` if it can't find MATLAB.

## Deliverable -> file map
| Rubric item | Where |
|---|---|
| Velocity/downrange/heat-rate vs altitude plots | `main_edl.m` -> `matlab/results/*.png` |
| Peak decel, peak heating + altitude, total heat load | `main_edl.m` console summary / `S` struct |
| Entry conditions | `edl_params.m` + `analysis/sweep_entry_angle.m` |
| Parachute size / load / terminal velocity / mass | `size_chutes.m`, `main_edl.m` |
| Heat shield sizing | TODO: `analysis/size_tps.m` (needs radiative heating + PICA data) |
| Structure sizing from peak g | TODO: `analysis/size_structure.m` |
| Landing attenuation | TODO (10 m/s on a dry lake bed needs crushable/airbag) |
| MEL / PEL | `spreadsheet/` -> course template |
| Telecom link budget | TODO: `analysis/link_budget.m` |
| Flight computer + triggers/faults | `flight_computer/edl_flight_computer.py` (+ table in report) |
