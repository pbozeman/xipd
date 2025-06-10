# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XIPD (Xilinx IBIS Package Delay) is a utility for computing package delays for Xilinx FPGA chips from IBIS files. This tool is necessary for PCB design when performing delay matching of parallel buses (like DDR3) and skew tuning within differential pairs.

The tool calculates per-pin package delays from Xilinx's IBIS files, which can be used in PCB design tools. It also optionally converts time delays to track lengths based on user-provided dielectric constants for compatibility with tools like KiCad.

## IBIS File Structure and Delay Calculation

The repository contains IBIS model files for various Xilinx FPGAs in the `ibis_files/` directory.

The package delay calculation uses primarily the Lumped LC Delay Approximation:
```
t_delay ≈ √(L × C)
```

Rather than the Elmore Delay (RC Dominated) method:
```
t_delay ≈ 0.69 × R × C
```

This is because:
- Inductance and capacitance dominate at high speeds (>100 MHz), especially for short interconnects like those in a package
- Resistance has minimal effect on propagation delay
- The die-to-pad connection behaves like a lumped LC structure, not an RC delay line

The implementation should focus on individual pin inductance and capacitance values rather than mutual inductance and capacitance matrices, as the effect is negligible for delay calculations.