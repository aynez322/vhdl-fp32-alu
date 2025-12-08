# FP32 ALU on Basys3 FPGA

IEEE-754 single-precision floating-point ALU with subtraction and division operations, controlled via buttons and displayed on 7-segment display.

## Hardware: Basys3 Board

### Controls

#### Buttons
- **Center (btnC)**: Reset the system
- **Up (btnU)**: Next test case
- **Down (btnD)**: Previous test case
- **Left (btnL)**: Toggle between SUB and DIV operations

#### Switches
- **sw[1:0]**: Select display mode
  - `00`: Show operand A (lower 16 bits)
  - `01`: Show operand B (lower 16 bits)
  - `10`: Show result (lower 16 bits)
  - `11`: Show test number (0-511)

### Indicators

#### 7-Segment Display
- 4-digit hexadecimal display showing selected value based on switch settings

#### LEDs
- **led[15:12]**: Operand A ROM index (0-15)
- **led[11:8]**: Operand B ROM index (0-15)
- **led[1]**: Operation mode (0=SUB, 1=DIV)
- **led[0]**: ALU ready signal

## Test ROM Values

The system includes 16 predefined floating-point values:

| Index | Hex Value  | Description   |
|-------|------------|---------------|
| 0     | 7F800000   | +Infinity     |
| 1     | FF800000   | -Infinity     |
| 2     | 00000000   | +0            |
| 3     | 80000000   | -0            |
| 4     | 7FC00000   | +NaN (quiet)  |
| 5     | FFC00000   | -NaN (quiet)  |
| 6     | 3F800000   | +1.0          |
| 7     | BF800000   | -1.0          |
| 8     | 40000000   | +2.0          |
| 9     | C0000000   | -2.0          |
| 10    | 40A00000   | +5.0          |
| 11    | C0A00000   | -5.0          |
| 12    | 41200000   | +10.0         |
| 13    | 40400000   | +3.0          |
| 14    | 3E800000   | +0.25         |
| 15    | 42C80000   | +100.0        |

## Test Cases

Total: **512 test cases** (256 subtraction + 256 division)
- Each test cycles through all 16×16 combinations of ROM values
- Tests cover edge cases: infinities, zeros, NaNs, normal numbers

## Usage Example

1. **Power on / Reset**: Press center button
2. **View test number**: Set switches to `11`
3. **Navigate tests**: Use Up/Down buttons
4. **View operand A**: Set switches to `00`
5. **View operand B**: Set switches to `01`
6. **View result**: Set switches to `10`
7. **Change operation**: Press Left button (LED[1] indicates SUB/DIV)

## Implementation Files

- `basys3_top.vhd`: Top-level module with button control and 7-segment display
- `SUB_DIV_FP_ALU.vhd`: FP32 ALU core (subtraction and division)
- `basys3.xdc`: Pin constraints for Basys3 board
- `tb_fp32_alu.vhd`: Testbench for simulation

## Building in Vivado

1. Create new RTL project
2. Add all `.vhd` files from `sources_1/new/`
3. Add `basys3.xdc` as constraints file
4. Set `basys3_top` as top module
5. Run Synthesis → Implementation → Generate Bitstream
6. Program Basys3 board

## Operation Algorithms

### Subtraction (A - B)
1. Handle special cases (NaN, Inf, zero)
2. Convert to A + (-B) by flipping sign of B
3. Align exponents (shift smaller mantissa)
4. Add/subtract mantissas based on effective signs
5. Normalize result (shift left/right to put leading 1 in position)
6. Handle overflow/underflow
7. Pack result to IEEE-754 format

### Division (A / B)
1. Handle special cases (NaN, Inf, zero, div-by-zero)
2. Compute sign: sign(A) XOR sign(B)
3. Compute exponent: exp(A) - exp(B) + bias
4. Divide mantissas using long division (24 iterations)
5. Normalize quotient
6. Handle overflow/underflow
7. Pack result to IEEE-754 format

## Notes

- Button debouncing implemented (10ms delay)
- 7-segment refresh rate: ~381 Hz (smooth, no flicker)
- Results displayed in hexadecimal
- All 512 test combinations accessible via button navigation
