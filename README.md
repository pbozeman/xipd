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

```tcl
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

The only required parameter is the pkg file name. If the stackup and
trace geometry is not provided, only on package timing delays are reported.

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

Pin       Bank      Site Type                          Delay   Stripline  Microstrip
                                                        (ps)      (mils)      (mils)
------------------------------------------------------------------------------------
A1        35        IO_L1N_T0_AD4N_35                 128.17       741.7       872.5
A2        N/A       GND                                  N/A         N/A         N/A
A3        N/A       GND                                  N/A         N/A         N/A
A4        216       MGTPTXN0_216                       94.66       547.8       644.4
A5        N/A       GND                                  N/A         N/A         N/A
...
Y1        34        IO_L5N_T0_34                      127.70       739.0       869.3
...
AB20      14        IO_L15N_T2_DQS_DOUT_CSO_B_14      104.82       606.5       713.5

....
```

## Overview

It is necessary to perform delay matching of parallel buses like DDR3
and skew turning within a differential pair when doing PCB routing. For
signals with tight tolerances, length matching the PCB traces is insufficient.
The on package delays of the FPGA or SOC must be included in the delay matching.

Unfortunately, Xilinx does not directly publish the package delays for their
chips. They do provide IBIS files. It is possible to calculate per pin calculation
delays from the IBIS files. That is the main purpose of this utility.

The per pin package delays can be entered directly into high end PCB design
tools like Altium in units of time. Unfortunately, KiCad only allows the
layout designer to enter pin package delays in terms of "track length." Given
that the propagation delay of a signal depends on a stackup dependent dielectric
constant, and differs for microstrip vs stripline. This tool also optionally
takes a dielectric constant as input and computes the delay in terms of length
in addition to time. [^1]

delay matching in KiCad. It appears that KiCad is changing to time based
delay matching, see: <https://gitlab.com/kicad/code/kicad/merge_requests/2212>. However, as I understand the KiCad release schedule, this won't be available
in a stable release until early 2026.

## Design

The following are my design notes, and also serve as AI context in developing
the utility.

Per pin package delays are computed from Xilinx's published IBIS files.

### Delay Calculation

There are 2 ways to calculate the per pin delays:

Lumped LC Delay Approximation:

```math
t_{\text{delay}} \approx \sqrt{L \cdot C}
```

Elmore Delay (RC Dominated):

```math
t_{\text{delay}} \approx 0.69 \cdot R \cdot C
```

<br>

I am not an EE, but AI says to use Lumped LC Delay Approximation because:

- Inductance and capacitance dominate at high speeds (>100 MHz),
  especially for short interconnects like those in a package.
- Resistance has minimal effect on propagation delay (it contributes more
  to signal attenuation than timing).
- The die-to-pad connection behaves like a lumped LC structure,
  not an RC delay line.

> [!Caution]
> TODO: validate this on Reddit

### Individual v.s. Mutual Inductance and Capacitance

In addition to the individual pin inductance and capacitance values,
the IBIS files include sparse matrices of mutual inductance and capacitance
of nearby pins. I'm not sure how to make use of this as it would seem to
require knowing signal details of the other pins. Further, AI indicated that
the basic calculations using individual pin data v.s. mutual pin data would be
measured in fractions of a picosecond. For purposes of delay w calculations, this
is negligible. It is also well beyond the PCB manufacturing tolerance.

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

#### Stripline

In a stripline (a trace fully embedded in dielectric), the electromagnetic
fields are entirely contained within the dielectric. So:

```math
\varepsilon_{\text{eff}} = \varepsilon_r
```

<br>

For example, JLC06161H-3313, a common 6 layer controlled impedance stackup
at JLCPCB has a dielectric constant of 4.16.

therefore:

```math
\varepsilon_{\text{eff}} = \varepsilon_r = 4.16
```

```math
t_d = \frac{\sqrt{\varepsilon_{\text{eff}}}}{c}
```

```math
t_d = \frac{\sqrt{4.16}}{3 \times 10^8}
     \approx 6.799 \times 10^{-9} \text{ s/m}
```

<br>

```math
t_d \approx 6.8 \, \text{ps/mm}
```

#### Microstrip

The effective dielectric constant `ε_eff` for a microstrip (air above,
dielectric below) is approximated by:

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

Given the same JLCPCB JLC06161H-3313 stackup used above, a 4.16 dielectric
constant, a prepreg thickness of 3.91mil, and a trace width of
6.16mil[^2], we have:

[^2]: This is the trace width for a 50ohm impedance for this stackup, per
the JLCPCB impedance calculator.

```math
\varepsilon_{\text{eff}} =
  \frac{4.16 + 1}{2} +
  \frac{4.16 - 1}{2} \cdot
  \frac{1}{\sqrt{1 + 12 \cdot \frac{3.91}{6.16}}}
```

```math
\varepsilon_{\text{eff}} =
  \approx 3.12
```

```math
t_d = \frac{\sqrt{3.12}}{3 \times 10^8}
    \approx 5.89 \times 10^{-9} \text{ s/m}
```

<br>

```math
t_d \approx 5.89 \, \text{ps/mm}

```

<br>

>[!Note]
> For this stackup, and trace geometry, stripline is roughly 15% slower than
> microstrip.

> [!Caution]
> TODO: the microstrip calculation assumes air above the trace. Double
> check if using a dielectric constant for soldermask makes a substantial
> difference in the results. JLCPCB provides some values on
> <https://jlcpcb.com/impedance>, but it is not immediately clear how these
> should be used and/or if they are so thin that both air and solder mask
> should be considered together.

#### Propagation Delay to Length

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
