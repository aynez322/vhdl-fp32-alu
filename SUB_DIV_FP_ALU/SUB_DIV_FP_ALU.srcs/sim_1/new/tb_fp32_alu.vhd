library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp32_alu_tb is
end entity;

architecture tb of fp32_alu_tb is
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

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal op    : std_logic_vector(1 downto 0) := (others => '0');
    signal a, b  : std_logic_vector(31 downto 0) := (others => '0');
    signal rdy   : std_logic;
    signal y     : std_logic_vector(31 downto 0);

    constant CLK_PERIOD : time := 10 ns;
    
    -- ROM with test values covering all special cases
    type fp_rom_type is array (0 to 15) of std_logic_vector(31 downto 0);
    constant TEST_ROM : fp_rom_type := (
        0  => x"7F800000",  -- +Inf
        1  => x"FF800000",  -- -Inf
        2  => x"00000000",  -- +0
        3  => x"80000000",  -- -0
        4  => x"7FC00000",  -- +qNaN
        5  => x"FFC00000",  -- -qNaN
        6  => x"3F800000",  -- +1.0
        7  => x"BF800000",  -- -1.0
        8  => x"40000000",  -- +2.0
        9  => x"C0000000",  -- -2.0
        10 => x"40A00000",  -- +5.0
        11 => x"C0A00000",  -- -5.0
        12 => x"41200000",  -- +10.0
        13 => x"40400000",  -- +3.0
        14 => x"3E800000",  -- +0.25
        15 => x"42C80000"   -- +100.0
    );

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
    
    function decode_value(slv: std_logic_vector(31 downto 0)) return string is
    begin
        if slv = x"7F800000" then return "+Inf       ";
        elsif slv = x"FF800000" then return "-Inf       ";
        elsif slv = x"00000000" then return "+0         ";
        elsif slv = x"80000000" then return "-0         ";
        elsif slv = x"7FC00000" then return "+qNaN       ";
        elsif slv = x"FFC00000" then return "-qNaN       ";
        elsif slv = x"3F800000" then return "+1.0       ";
        elsif slv = x"BF800000" then return "-1.0       ";
        elsif slv = x"40000000" then return "+2.0       ";
        elsif slv = x"C0000000" then return "-2.0       ";
        elsif slv = x"40A00000" then return "+5.0       ";
        elsif slv = x"C0A00000" then return "-5.0       ";
        elsif slv = x"41200000" then return "+10.0      ";
        elsif slv = x"40400000" then return "+3.0       ";
        elsif slv = x"3E800000" then return "+0.25      ";
        elsif slv = x"42C80000" then return "+100.0     ";
        else return "UNKNOWN    ";
        end if;
    end function;


begin
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

    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    stim_proc: process
        variable test_count : integer := 0;
    begin
        rst <= '1';
        wait for 2*CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;
        report "===== SUBTRACTION TESTS (op=00) =====";
        for i in 0 to 15 loop
            for j in 0 to 15 loop
                test_count := test_count + 1;
                op <= "00"; -- SUB
                a <= TEST_ROM(i);
                b <= TEST_ROM(j);
                wait for CLK_PERIOD;
                wait until rising_edge(clk) and rdy = '1';
                report "Test " & integer'image(test_count) & ": " & 
                       decode_value(TEST_ROM(i)) & " - " & 
                       decode_value(TEST_ROM(j)) & " = " & 
                       to_hex_string(y);
                wait for CLK_PERIOD;
            end loop;
        end loop;
        
        report "";
        report "===== DIVISION TESTS (op=01) =====";
        for i in 0 to 15 loop
            for j in 0 to 15 loop
                test_count := test_count + 1;
                op <= "01"; -- DIV
                a <= TEST_ROM(i);
                b <= TEST_ROM(j);
                wait for CLK_PERIOD;
                wait until rising_edge(clk) and rdy = '1';
                report "Test " & integer'image(test_count) & ": " & 
                       decode_value(TEST_ROM(i)) & " / " & 
                       decode_value(TEST_ROM(j)) & " = " & 
                       to_hex_string(y);
                wait for CLK_PERIOD;
            end loop;
        end loop;
        wait for 5*CLK_PERIOD;
        std.env.stop;
    end process;
end architecture tb;
