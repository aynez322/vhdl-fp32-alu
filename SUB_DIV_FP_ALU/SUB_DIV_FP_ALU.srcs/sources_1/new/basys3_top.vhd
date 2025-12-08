library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity basys3_top is
    port (
        clk       : in  std_logic;
        btnC      : in  std_logic;
        btnU      : in  std_logic;
        btnD      : in  std_logic;
        btnL      : in  std_logic;
        sw        : in  std_logic_vector(1 downto 0);
        seg       : out std_logic_vector(6 downto 0);
        an        : out std_logic_vector(3 downto 0);
        led       : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of basys3_top is
    
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
    
    type fp_rom_type is array (0 to 15) of std_logic_vector(31 downto 0);
    constant TEST_ROM : fp_rom_type := (
        0  => x"7F800000",  -- +Infinity
        1  => x"FF800000",  -- -Infinity
        2  => x"00000000",  -- +0
        3  => x"80000000",  -- -0
        4  => x"7FC00000",  -- +NaN (quiet)
        5  => x"FFC00000",  -- -NaN (quiet)
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
    
    signal rst_sync : std_logic := '0';
    signal op_mode  : std_logic_vector(1 downto 0) := "00";  -- "00" = SUB, "01" = DIV
    signal test_idx_a : integer range 0 to 15 := 0;
    signal test_idx_b : integer range 0 to 15 := 0;
    signal test_number : integer range 0 to 511 := 0;
    signal alu_a, alu_b : std_logic_vector(31 downto 0);
    signal alu_y : std_logic_vector(31 downto 0);
    signal alu_rdy : std_logic;
    signal btnU_db, btnD_db, btnL_db : std_logic := '0';
    signal btnU_prev, btnD_prev, btnL_prev : std_logic := '0';
    signal btnU_edge, btnD_edge, btnL_edge : std_logic := '0';
    signal display_value : std_logic_vector(15 downto 0);
    signal refresh_counter : unsigned(19 downto 0) := (others => '0');
    signal digit_select : unsigned(1 downto 0);
    signal current_digit : std_logic_vector(3 downto 0);
    
begin
    alu_inst: fp32_alu
        port map (
            clk => clk,
            rst => rst_sync,
            op  => op_mode,
            a   => alu_a,
            b   => alu_b,
            rdy => alu_rdy,
            y   => alu_y
        );
    
    rst_sync <= btnC;
    alu_a <= TEST_ROM(test_idx_a);
    alu_b <= TEST_ROM(test_idx_b);
    process(clk)
        variable debounce_cnt_u : integer range 0 to 1000000 := 0;
        variable debounce_cnt_d : integer range 0 to 1000000 := 0;
        variable debounce_cnt_l : integer range 0 to 1000000 := 0;
    begin
        if rising_edge(clk) then
            if btnU = '1' then
                if debounce_cnt_u < 1000000 then
                    debounce_cnt_u := debounce_cnt_u + 1;
                else
                    btnU_db <= '1';
                end if;
            else
                debounce_cnt_u := 0;
                btnU_db <= '0';
            end if;
            if btnD = '1' then
                if debounce_cnt_d < 1000000 then
                    debounce_cnt_d := debounce_cnt_d + 1;
                else
                    btnD_db <= '1';
                end if;
            else
                debounce_cnt_d := 0;
                btnD_db <= '0';
            end if;
            if btnL = '1' then
                if debounce_cnt_l < 1000000 then
                    debounce_cnt_l := debounce_cnt_l + 1;
                else
                    btnL_db <= '1';
                end if;
            else
                debounce_cnt_l := 0;
                btnL_db <= '0';
            end if;
            btnU_prev <= btnU_db;
            btnD_prev <= btnD_db;
            btnL_prev <= btnL_db;
            btnU_edge <= btnU_db and not btnU_prev;
            btnD_edge <= btnD_db and not btnD_prev;
            btnL_edge <= btnL_db and not btnL_prev;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_sync = '1' then
                test_number <= 0;
                test_idx_a <= 0;
                test_idx_b <= 0;
                op_mode <= "00";
            else
                if btnL_edge = '1' then
                    if op_mode = "00" then
                        op_mode <= "01";  -- DIV
                    else
                        op_mode <= "00";  -- SUB
                    end if;
                end if;
                
                if btnU_edge = '1' then
                    if test_idx_b < 15 then
                        test_idx_b <= test_idx_b + 1;
                    elsif test_idx_a < 15 then
                        test_idx_a <= test_idx_a + 1;
                        test_idx_b <= 0;
                    else
                        -- Wrap around
                        test_idx_a <= 0;
                        test_idx_b <= 0;
                    end if;
                    
                    if test_number < 511 then
                        test_number <= test_number + 1;
                    else
                        test_number <= 0;
                    end if;
                end if;
        
                if btnD_edge = '1' then
                    if test_idx_b > 0 then
                        test_idx_b <= test_idx_b - 1;
                    elsif test_idx_a > 0 then
                        test_idx_a <= test_idx_a - 1;
                        test_idx_b <= 15;
                    else
                        test_idx_a <= 15;
                        test_idx_b <= 15;
                    end if;
                    if test_number > 0 then
                        test_number <= test_number - 1;
                    else
                        test_number <= 511;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(sw, alu_a, alu_b, alu_y, test_number)
    begin
        case sw is
            when "00" =>
                display_value <= alu_a(15 downto 0);
            when "01" =>
                display_value <= alu_b(15 downto 0);
            when "10" =>
                display_value <= alu_y(15 downto 0);
            when "11" =>
                display_value <= std_logic_vector(to_unsigned(test_number, 16));
            when others =>
                display_value <= (others => '0');
        end case;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            refresh_counter <= refresh_counter + 1;
        end if;
    end process;
    
    digit_select <= refresh_counter(19 downto 18);
    
    process(digit_select, display_value)
    begin
        case digit_select is
            when "00" =>
                an <= "1110";
                current_digit <= display_value(3 downto 0);
            when "01" =>
                an <= "1101";
                current_digit <= display_value(7 downto 4);
            when "10" =>
                an <= "1011";
                current_digit <= display_value(11 downto 8);
            when "11" =>
                an <= "0111";
                current_digit <= display_value(15 downto 12);
            when others =>
                an <= "1111";
                current_digit <= "0000";
        end case;
    end process;
    
    process(current_digit)
    begin
        case current_digit is
            when x"0" => seg <= "1000000";  -- 0
            when x"1" => seg <= "1111001";  -- 1
            when x"2" => seg <= "0100100";  -- 2
            when x"3" => seg <= "0110000";  -- 3
            when x"4" => seg <= "0011001";  -- 4
            when x"5" => seg <= "0010010";  -- 5
            when x"6" => seg <= "0000010";  -- 6
            when x"7" => seg <= "1111000";  -- 7
            when x"8" => seg <= "0000000";  -- 8
            when x"9" => seg <= "0010000";  -- 9
            when x"A" => seg <= "0001000";  -- A
            when x"B" => seg <= "0000011";  -- b
            when x"C" => seg <= "1000110";  -- C
            when x"D" => seg <= "0100001";  -- d
            when x"E" => seg <= "0000110";  -- E
            when x"F" => seg <= "0001110";  -- F
            when others => seg <= "1111111";  -- blank
        end case;
    end process;
    
    led(15 downto 12) <= std_logic_vector(to_unsigned(test_idx_a, 4));
    led(11 downto 8)  <= std_logic_vector(to_unsigned(test_idx_b, 4));
    led(7 downto 2)   <= (others => '0');
    led(1)            <= op_mode(0);
    led(0)            <= alu_rdy;

end architecture rtl;
