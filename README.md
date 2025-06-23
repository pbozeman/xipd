# Xilinx Package Delay

Compute package delays for Xilinx chips from exported Vivado pkg files,
including converting delays to lengths that can be used in KiCad track tuning.[^1]

[^1]: The first version of this utility parsed the Xilinx Ibis files. The utility name was therefor **X**ilinx **I**BIS **P**ackage **D**elay. It now computes
trace delays off of Vivado exports. Vivado model the delays slightly
differently, and presumably, more accurately.
This is now the **XI**linx **P**ackage **D**elay utility.

For the microstrip use case, run the tool multiple times if different trace
widths are needed, e.g. 50ohm for DDR3 and 100ohm differential pairs for
GTP traces.

## Usage

Export one or more parts from Vivado by performing the following in
the TCL console:

```text
# customize this parts list to include one or more packages
set partslist {
    xc7a50tfgg484-1
    xc7z020clg484-1
}

foreach p $partslist {
    puts $p
    create_project -in_memory -part $p
    set_property design_mode PinPlanning [current_fileset]
    open_io_design -name io_1
    write_csv -force $p.pkg
    close_project
}
```

Run xipd with the exported package and supply your stackup and trace geometry.

Example:

```bash
./xipd pkgs/xc7a50tfgg484-1.pkg \
     --dielectric-constant 4.16 \
     --prepreg-height 3.91      \
     --trace-width 3.68         \
     --output-units mils
```

Results:

```text
Processing package file: pkgs/xc7a50tfgg484-1.pkg
Found 484 pins in the package file

PCB Stack-up Parameters:
  Dielectric Constant (εr): 4.16
  Prepreg Height: 3.91
  Trace Width: 3.68
  Height/Width Ratio: 1.062
  Effective Dielectric (Stripline): 4.16
  Effective Dielectric (Microstrip): 3.01
  Propagation Delay (Stripline): 6.80 ps/mm
  Propagation Delay (Microstrip): 5.78 ps/mm

Pin Data:

Pin       Bank      Site Type                          Delay   Microstrip  Stripline
                                                        (ps)      (mils)      (mils)
------------------------------------------------------------------------------------
A1        35        IO_L1N_T0_AD4N_35                 128.17       872.5       741.7
A2        N/A       GND                                  N/A         N/A         N/A
A3        N/A       GND                                  N/A         N/A         N/A
A4        216       MGTPTXN0_216                       94.66       644.4       547.8
A5        N/A       GND                                  N/A         N/A         N/A
...
```

## Overview

It is necessary to perform delay matching of parallel buses like DDR3
and skew turning within a differential pair when doing PCB routing. For
signals with tight tolerances, length matching the PCB traces is insufficient.
The on package delays of the FPGA or SOC must be included in the delay matching.

These delays can be exported from Vivado using the commands at the top
of the readme.

The per pin package delays can be entered directly into high end PCB design
tools like Altium in units of time. Unfortunately, KiCad only allows the
layout designer to enter pin package delays in terms of "track length." Given
that the propagation delay of a signal depends on a stackup dependent dielectric
constant, and differs for microstrip vs stripline. This tool also optionally
takes a dielectric constant as input and computes the delay in terms of length
in addition to time. [^2]

[^2]: This also means its difficult, if not impossible, to do multi layer
delay matching in KiCad. It appears that KiCad is changing to time based
delay matching, see: <https://gitlab.com/kicad/code/kicad/merge_requests/2212>.
However, as I understand the KiCad release schedule, this won't be available
in a stable release until early 2026.

## Design

The following are my design notes, and also serve as AI context in developing
the utility.

### Time Based Package Delay

The first version of the utility calculated packages delays using
Lumped LC Delay Approximation, with per-pin L and C parsed from the
Xilinx IBIS files. The following formula was used:

```math
t_{\text{delay}} \approx \sqrt{L \cdot C}

```

Delays computed in this manor were consistently 2-4ps shorter than what
is exported from Vivado. I assume that Vivado is doing a more
advanced simulation, or potentially taking mutual capacitance or inductance
into account.

>[!Note]
> This version uses the average of the min and max delays reported by Vivado.

---

### Length Calculation

The delay computed above must be converted to units of length for use in KiCad.
This means calculating both the stripline and microstrip lengths so that
the appropriate value can be used depending on which layer the signal is routed
on.

#### Propagation Delay – General Formula

The propagation delay per unit length is given by:

```math
t_d = \frac{\sqrt{\varepsilon_{\text{eff}}}}{c}
```

Where:

- t_d: propagation delay (s/m)
- ε_eff: effective dielectric constant
- c: speed of light ≈ 3 × 10⁸ m/s

---

#### Microstrip

The effective dielectric constant `ε_eff` for a microstrip (air above,
dielectric below) is approximated by[^3]:

[^3]: <https://en.wikipedia.org/wiki/Microstrip#Characteristic_impedance>

```math
\varepsilon_{\text{eff}} =
  \frac{\varepsilon_r + 1}{2} + \frac{\varepsilon_r - 1}{2}
  \cdot
  \frac{1}{\sqrt{1 + 12 \cdot \frac{h}{w}}}
```

Where:

- `ε_r` = Relative permittivity (dielectric constant) of the substrate
- `h` = Height of the dielectric (distance from trace to reference plane)
- `w` = Width of the microstrip trace
- (All dimensions must use the same unit, e.g., mm or mils)

---

#### Stripline

In a stripline (a trace fully embedded in dielectric), the electromagnetic
fields are contained entirely within the dielectric. If the dielectric above
and below the trace is the same, and the trace is centered, then:

```math
\varepsilon_{\text{eff}} = \varepsilon_r
```

Where `ε_r` is the relative permittivity of the dielectric.

However, if the trace is off-center or the dielectrics above and below differ,
a better approximation is:

```math
\varepsilon_{\text{eff}} =
  \frac{\varepsilon_{r1} \cdot h_1 + \varepsilon_{r2} \cdot h_2}
       {h_1 + h_2}
```

Where:

- `ε_r1` = Relative permittivity of the dielectric **above** the trace
- `ε_r2` = Relative permittivity of the dielectric **below** the trace
- `h₁` = Distance from the **center of the trace to the upper reference plane**
- `h₂` = Distance from the **center of the trace to the lower reference plane**

This is a weighted average of the permittivities, accounting for unequal
dielectric regions surrounding the trace.

---

### Example Delays for JLCPCB 6 Layer stackup

The following examples use the default 6 layer impedance controlled stackup
from JLCPCB (JLC06161H-3313):

| Layer   | Material                    | Thickness (mil) | Thickness (mm) |
| ------- | --------------------------- | --------------- | -------------- |
| L1      | Outer Copper Weight 1 oz    | 1.38            | 0.0350         |
| Prepreg | 3313 RC57%                  | 3.91            | 0.0994         |
| L2      | Inner Copper Weight         | 0.60            | 0.0152         |
| Core    | 0.55 mm H (no copper)       | 21.65           | 0.5500         |
| L3      | Inner Copper Weight         | 0.60            | 0.0152         |
| Prepreg | 2116 RC54%                  | 4.28            | 0.1088         |
| L4      | Inner Copper Weight         | 0.60            | 0.0152         |
| Core    | 0.55 mm H (no copper)       | 21.65           | 0.5500         |
| L5      | Inner Copper Weight         | 0.60            | 0.0152         |
| Prepreg | 3313 RC57%                  | 3.91            | 0.0994         |
| L6      | Outer Copper Weight 1 oz    | 1.38            | 0.0350         |

Dielectric constants for JLCPCB prepreg and cores:

| Prepreg Type | Dielectric Constant |
| ------------ | ------------------- |
| 7628         | 4.4                 |
| 3313         | 4.1                 |
| 1080         | 3.91                |
| 2116         | 4.16                |

---

#### Microstrip Example (Routing on L1)

If routing on **L1**, the return plane is **L2**, separated by:

- Dielectric: Prepreg 3313
- Dielectric constant: `ε_r = 4.10`
- Thickness: `h = 3.91 mil`
- Trace width: `w = 6.16 mil` (for 50 Ω characteristic impedance)

```math
\varepsilon_{\text{eff}} =
  \frac{4.10 + 1}{2} +
  \frac{4.10 - 1}{2} \cdot
  \frac{1}{\sqrt{1 + 12 \cdot \frac{3.91}{6.16}}}
  \approx 3.087
```

```math
t_d = \frac{\sqrt{3.087}}{3 \times 10^8}
    \approx 5.86 \, \text{ps/mm}
```

---

#### Stripline Example (Routing on L3)

If routing on **L3**, the return planes are **L2 (above)** and **L4 (below)**.

- Dielectric above trace: Core 3313 → `ε_r1 = 4.10`, `h₁ = 0.550 mm`
- Dielectric below trace: Prepreg 2116 → `ε_r2 = 4.16`, `h₂ = 0.1088 mm`

```math
\varepsilon_{\text{eff}} =
  \frac{4.10 \cdot 0.550 + 4.16 \cdot 0.1088}{0.550 + 0.1088}
  \approx 4.112
```

```math
t_d = \frac{\sqrt{4.112}}{3 \times 10^8}
    \approx 6.77 \, \text{ps/mm}
```

---

### Summary

| Geometry           | ε_eff | Delay (ps/mm) |
|--------------------|--------|----------------|
| Microstrip (L1)    | 3.087  | 5.86           |
| Stripline (L3)     | 4.112  | 6.77           |

>[!Note]
> For this stackup and trace geometry, stripline propagation is approximately
> 15% slower than microstrip.

---

### Propagation Delay to Length

The user provides the dielectric constant, prepeg height, and trace width.
The formulas defined above are used to calculate the propagation delay and
then converted to lengths using:

```math
\ell = \frac{t}{t_d}
```

Where:

- ℓ: equivalent PCB track length for the die to pad delay
- t: die to pad delay computed using the LC Delay Approximation
- t_d: propagation delay computed from stackup and trace geometry
