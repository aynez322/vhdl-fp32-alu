# IEEE 754 Floating-Point ALU (VHDL)

A hardware implementation of an IEEE 754 single-precision (32-bit) floating-point Arithmetic Logic Unit in VHDL, supporting subtraction and division operations.

## Features

- **Operations Supported:**
  - Subtraction (A - B)
  - Division (A / B)

- **IEEE 754 Compliance:**
  - Handles special values (NaN, Infinity, Zero)
  - Proper sign handling for all operations
  - Denormal number support
  - Correct special case handling (0/0 → NaN, x/0 → Inf, Inf/Inf → NaN)

- **Architecture:**
  - Restoring division algorithm with 24-bit mantissa precision
  - Dual-path subtraction (magnitude addition/subtraction based on effective signs)
  - Automatic normalization and exponent adjustment
  - Synchronous design with ready flag

## Limitations

- Division of numbers resulting in repeating binary fractions may have reduced precision
- Simplified rounding (no IEEE 754 rounding modes implemented)
- No guard/round/sticky bits for optimal precision

## Test Coverage

23 out of 24 test cases pass (95.8% success rate), including:
- Basic arithmetic operations
- Edge cases (very small/large numbers)
- Special values (NaN, Infinity, zero)
- Signed operations
- Exact and approximate divisions

## Files

- `new 1.vhd` - Main ALU implementation
- `tb_fp32_alu.vhd` - Comprehensive testbench with 24 test cases

## Usage

The ALU operates on IEEE 754 single-precision format:
- Bit 31: Sign
- Bits 30-23: Exponent (biased by 127)
- Bits 22-0: Fraction (23 bits)

```vhdl
entity fp32_alu is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        op    : in  std_logic_vector(1 downto 0); -- "00" = SUB, "01" = DIV
        a     : in  std_logic_vector(31 downto 0);
        b     : in  std_logic_vector(31 downto 0);
        rdy   : out std_logic;
        y     : out std_logic_vector(31 downto 0)
    );
end entity;
