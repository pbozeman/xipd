# Xilinx IBIS Package Delay

Compute package delays for Xilinx chips from IBIS files.

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

[^1]: This also means its difficult, if not impossible, to do multi layer
delay matching in KiCad. It appears that KiCad is changing to time based
delay matching, see: <https://gitlab.com/kicad/code/kicad/merge_requests/2212>. However, as I understand the KiCad release schedule, this won't be available
in a stable release until early 2026.

## Design Overview

The following are my design notes, and also serve as AI context in developing
the utility.

Per pin package delays are computed from Xilinx's published IBIS files.

### Delay Calculation

There are 2 ways to calculate the per pin delays:

#### Lumped LC Delay Approximation

```
t_delay ≈ √(L × C)
```

#### Elmore Delay (RC Dominated)

```
t_delay ≈ 0.69 × R × C
```

I am not an EE, but AI says to use Lumped LC Delay Approximation because:

* Inductance and capacitance dominate at high speeds (>100 MHz),
  especially for short interconnects like those in a package.
* Resistance has minimal effect on propagation delay (it contributes more
  to signal attenuation than timing).
* The die-to-pad connection behaves like a lumped LC structure,
  not an RC delay line.

> [!Caution] TODO: validate this on Reddit

### Individual v.s. Mutual Inductance and Capacitance

In addition to the individual pin inductance and capacitance values,
the IBIS files include sparse matrices of mutual inductance and capacitance
of nearby pins. I'm not sure how to make use of this as it would seem to
require knowing signal details of the other pins. Further, AI indicated that
the basic calculations using individual pin data v.s. mutual pin data would be
measured in fractions of a picosecond. For purposes of delay w calculations, this
is negligible. It is also well beyond the PCB manufacturing tolerance.
