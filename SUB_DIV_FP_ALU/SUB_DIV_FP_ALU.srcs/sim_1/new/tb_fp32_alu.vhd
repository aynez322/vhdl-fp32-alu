-- tb_fp32_alu.vhd
-- Testbench for fp32_alu (IEEE 754 single precision ALU)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp32_alu_tb is
end entity;

architecture tb of fp32_alu_tb is

    -- DUT component declaration
    component fp32_alu is
        port (
            clk   : in  std_logic;
            rst   : in  std_logic;
            op    : in  std_logic_vector(1 downto 0);
            a     : in  std_logic_vector(31 downto 0);
            b     : in  std_logic_vector(31 downto 0);
            rdy   : out std_logic;
            y     : out std_logic_vector(31 downto 0)
        );
    end component;

    -- Signals
    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal op    : std_logic_vector(1 downto 0) := (others => '0');
    signal a, b  : std_logic_vector(31 downto 0) := (others => '0');
    signal rdy   : std_logic;
    signal y     : std_logic_vector(31 downto 0);

    constant CLK_PERIOD : time := 10 ns;

    -- Helper function to convert real to IEEE754 single precision
    function real_to_fp32(r: real) return std_logic_vector is
        variable sign  : std_logic;
        variable exp   : integer;
        variable frac  : real;
        variable mant  : unsigned(22 downto 0);
        variable e     : unsigned(7 downto 0);
        variable res   : std_logic_vector(31 downto 0);
    begin
        if r = 0.0 then
            return x"00000000";
        end if;

        if r < 0.0 then
            sign := '1';
            frac := -r;
        else
            sign := '0';
            frac := r;
        end if;

        exp := 0;
        while frac >= 2.0 loop
            frac := frac / 2.0;
            exp := exp + 1;
        end loop;
        while frac < 1.0 loop
            frac := frac * 2.0;
            exp := exp - 1;
        end loop;

        frac := frac - 1.0;
        mant := to_unsigned(integer(frac * (2.0**23)), 23);
        e := to_unsigned(exp + 127, 8);

        res(31) := sign;
        res(30 downto 23) := std_logic_vector(e);
        res(22 downto 0) := std_logic_vector(mant);
        return res;
    end function;

    -- Helper to display FP32 value as hex string
    function to_hex_string(slv: std_logic_vector(31 downto 0)) return string is
        variable hexchars : string(1 to 8);
        variable temp : std_logic_vector(31 downto 0) := slv;
        variable nibble : std_logic_vector(3 downto 0);
        constant hexmap : string(1 to 16) := "0123456789ABCDEF";
    begin
        for i in 0 to 7 loop
            nibble := temp(31 - i*4 downto 28 - i*4);
            hexchars(i+1) := hexmap(to_integer(unsigned(nibble)) + 1);
        end loop;
        return hexchars;
    end function;

begin
    -- Instantiate the ALU
    dut: fp32_alu
        port map (
            clk => clk,
            rst => rst,
            op  => op,
            a   => a,
            b   => b,
            rdy => rdy,
            y   => y
        );

    -- Clock generation
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Test sequence
    stim_proc: process
    begin
        -- Reset
        rst <= '1';
        wait for 2*CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        report "===== TEST 1: Simple Subtraction =====";
        op <= "00"; -- SUB
        a <= real_to_fp32(10.0);
        b <= real_to_fp32(3.5);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 10.0, B = 3.5, A - B = " & to_hex_string(y);
        wait for CLK_PERIOD;

        report "===== TEST 2: Simple Division =====";
        op <= "01"; -- DIV
        a <= real_to_fp32(10.0);
        b <= real_to_fp32(2.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 10.0, B = 2.0, A / B = " & to_hex_string(y);
        wait for CLK_PERIOD;

        report "===== TEST 3: Division by Zero =====";
        op <= "01";
        a <= real_to_fp32(5.0);
        b <= x"00000000"; -- zero
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 5.0, B = 0.0, A / B = " & to_hex_string(y) & " (should be +Inf = 7F800000)";
        wait for CLK_PERIOD;

        report "===== TEST 4: Subtraction with Negative =====";
        op <= "00";
        a <= real_to_fp32(-2.0);
        b <= real_to_fp32(5.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = -2.0, B = 5.0, A - B = " & to_hex_string(y);
        wait for CLK_PERIOD;

        report "===== TEST 5: Inf - Inf (NaN case) =====";
        op <= "00";
        a <= x"7F800000"; -- +Inf
        b <= x"7F800000"; -- +Inf
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = +Inf, B = +Inf, A - B = " & to_hex_string(y) & " (should be NaN = 7FC00000)";
        wait for CLK_PERIOD;

        report "===== TEST 6: Inf / finite =====";
        op <= "01";
        a <= x"7F800000"; -- +Inf
        b <= x"3F800000"; -- +1.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = +Inf, B = 1.0, A / B = " & to_hex_string(y) & " (should be +Inf = 7F800000)";
        wait for CLK_PERIOD;

        report "===== TEST 7: Division 1.0 / 4.0 =====";
        op <= "01";
        a <= x"3F800000"; -- 1.0
        b <= x"40800000"; -- 4.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 1.0, B = 4.0, A / B = " & to_hex_string(y) & " (should be 0.25 = 3E800000)";
        wait for CLK_PERIOD;

        report "===== TEST 8: Subtraction 5.0 - 2.0 =====";
        op <= "00";
        a <= real_to_fp32(5.0);
        b <= real_to_fp32(2.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 5.0, B = 2.0, A - B = " & to_hex_string(y) & " (should be 3.0 = 40400000)";
        wait for CLK_PERIOD;

        report "===== TEST 9: Subtraction to Zero (5.0 - 5.0) =====";
        op <= "00";
        a <= real_to_fp32(5.0);
        b <= real_to_fp32(5.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 5.0, B = 5.0, A - B = " & to_hex_string(y) & " (should be 0.0 = 00000000)";
        wait for CLK_PERIOD;

        report "===== TEST 10: Subtraction 0.0 - 5.0 =====";
        op <= "00";
        a <= x"00000000"; -- 0.0
        b <= real_to_fp32(5.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 0.0, B = 5.0, A - B = " & to_hex_string(y) & " (should be -5.0 = C0A00000)";
        wait for CLK_PERIOD;

        report "===== TEST 11: Subtraction -5.0 - (-5.0) =====";
        op <= "00";
        a <= real_to_fp32(-5.0);
        b <= real_to_fp32(-5.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = -5.0, B = -5.0, A - B = " & to_hex_string(y) & " (should be 0.0 = 00000000)";
        wait for CLK_PERIOD;

        report "===== TEST 12: Division 10.0 / 1.0 =====";
        op <= "01";
        a <= real_to_fp32(10.0);
        b <= x"3F800000"; -- 1.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 10.0, B = 1.0, A / B = " & to_hex_string(y) & " (should be 10.0 = 41200000)";
        wait for CLK_PERIOD;

        report "===== TEST 13: Division 7.0 / 7.0 =====";
        op <= "01";
        a <= real_to_fp32(7.0);
        b <= real_to_fp32(7.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 7.0, B = 7.0, A / B = " & to_hex_string(y) & " (should be 1.0 = 3F800000)";
        wait for CLK_PERIOD;

        report "===== TEST 14: Division -10.0 / 2.0 =====";
        op <= "01";
        a <= real_to_fp32(-10.0);
        b <= real_to_fp32(2.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = -10.0, B = 2.0, A / B = " & to_hex_string(y) & " (should be -5.0 = C0A00000)";
        wait for CLK_PERIOD;

        report "===== TEST 15: Division 10.0 / -2.0 =====";
        op <= "01";
        a <= real_to_fp32(10.0);
        b <= real_to_fp32(-2.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 10.0, B = -2.0, A / B = " & to_hex_string(y) & " (should be -5.0 = C0A00000)";
        wait for CLK_PERIOD;

        report "===== TEST 16: Division -10.0 / -2.0 =====";
        op <= "01";
        a <= real_to_fp32(-10.0);
        b <= real_to_fp32(-2.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = -10.0, B = -2.0, A / B = " & to_hex_string(y) & " (should be 5.0 = 40A00000)";
        wait for CLK_PERIOD;

        report "===== TEST 17: Division 8.0 / 4.0 =====";
        op <= "01";
        a <= real_to_fp32(8.0);
        b <= real_to_fp32(4.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 8.0, B = 4.0, A / B = " & to_hex_string(y) & " (should be 2.0 = 40000000)";
        wait for CLK_PERIOD;

        report "===== TEST 18: Division 1.0 / 8.0 =====";
        op <= "01";
        a <= x"3F800000"; -- 1.0
        b <= real_to_fp32(8.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 1.0, B = 8.0, A / B = " & to_hex_string(y) & " (should be 0.125 = 3E000000)";
        wait for CLK_PERIOD;

        report "===== TEST 19: Division 0.0 / 0.0 (NaN) =====";
        op <= "01";
        a <= x"00000000"; -- 0.0
        b <= x"00000000"; -- 0.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 0.0, B = 0.0, A / B = " & to_hex_string(y) & " (should be NaN)";
        wait for CLK_PERIOD;

        report "===== TEST 20: Subtraction 0.0 - 0.0 =====";
        op <= "00";
        a <= x"00000000"; -- 0.0
        b <= x"00000000"; -- 0.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 0.0, B = 0.0, A - B = " & to_hex_string(y) & " (should be 0.0 = 00000000)";
        wait for CLK_PERIOD;

        report "===== TEST 21: NaN - 5.0 (NaN propagation) =====";
        op <= "00";
        a <= x"7FC00000"; -- NaN
        b <= real_to_fp32(5.0);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = NaN, B = 5.0, A - B = " & to_hex_string(y) & " (should be NaN = 7FC00000)";
        wait for CLK_PERIOD;

        report "===== TEST 22: 5.0 / NaN (NaN propagation) =====";
        op <= "01";
        a <= real_to_fp32(5.0);
        b <= x"7FC00000"; -- NaN
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 5.0, B = NaN, A / B = " & to_hex_string(y) & " (should be NaN = 7FC00000)";
        wait for CLK_PERIOD;

        report "===== TEST 23: Division 10.0 / 3.0 (with remainder) =====";
        op <= "01";
        a <= x"41200000";  -- This is definitely 10.0
        b <= x"40400000";  -- This is definitely 3.0
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 10.0, B = 3.0, A / B = " & to_hex_string(y) & " (should be ~3.333 = 40555555)";
        wait for CLK_PERIOD;

        report "===== TEST 24: Subtraction 100.0 - 0.001 =====";
        op <= "00";
        a <= real_to_fp32(100.0);
        b <= real_to_fp32(0.001);
        wait for 3*CLK_PERIOD;
        wait until rising_edge(clk) and rdy = '1';
        report "A = 100.0, B = 0.001, A - B = " & to_hex_string(y) & " (should be ~99.999)";
        wait for CLK_PERIOD;

        wait for 5*CLK_PERIOD;
        report "==== TESTBENCH COMPLETED SUCCESSFULLY ====";
        std.env.stop;
    end process;

end architecture tb;
