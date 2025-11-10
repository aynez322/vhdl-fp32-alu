library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fp32_alu is
    port (
        clk   : in  std_logic := '0';
        rst   : in  std_logic := '0';
        op    : in  std_logic_vector(1 downto 0); -- "00" = SUB, "01" = DIV
        a     : in  std_logic_vector(31 downto 0);
        b     : in  std_logic_vector(31 downto 0);
        rdy   : out std_logic;
        y     : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of fp32_alu is

    function get_sign(x: std_logic_vector(31 downto 0)) return std_logic is
    begin return x(31); end function;
    function get_exp(x: std_logic_vector(31 downto 0)) return unsigned is
    begin return unsigned(x(30 downto 23)); end function;
    function get_frac(x: std_logic_vector(31 downto 0)) return unsigned is
    begin return unsigned(x(22 downto 0)); end function;
    function pack_fp(sign: std_logic; exp: unsigned(7 downto 0); frac: unsigned(22 downto 0)) return std_logic_vector is
        variable outv: std_logic_vector(31 downto 0);
    begin
        outv(31) := sign;
        outv(30 downto 23) := std_logic_vector(exp);
        outv(22 downto 0) := std_logic_vector(frac);
        return outv;
    end function;

    function is_zero(exp: unsigned(7 downto 0); frac: unsigned(22 downto 0)) return boolean is
    begin
        return (exp = x"00") and (frac = (22 downto 0 => '0'));
    end function;
    function is_inf(exp: unsigned(7 downto 0); frac: unsigned(22 downto 0)) return boolean is
    begin
        return (exp = x"FF") and (frac = (22 downto 0 => '0'));
    end function;
    function is_nan(exp: unsigned(7 downto 0); frac: unsigned(22 downto 0)) return boolean is
    begin
        return (exp = x"FF") and (frac /= (22 downto 0 => '0'));
    end function;
    signal result_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal ready_reg  : std_logic := '0';
    constant BIAS : integer := 127;

begin

    process(clk, rst)
        variable sign_a, sign_b : std_logic;
        variable exp_a, exp_b : unsigned(7 downto 0);
        variable frac_a, frac_b : unsigned(22 downto 0);
        variable mant_a, mant_b : unsigned(23 downto 0);
        variable res_sign   : std_logic;
        variable res_exp    : integer;
        variable res_frac   : unsigned(22 downto 0);
        variable special_out : std_logic_vector(31 downto 0);
        variable special_ready : std_logic;
        -- Subtraction variables
        variable sign_res : std_logic;
        variable exp_large, exp_small : unsigned(7 downto 0);
        variable mant_large, mant_small : unsigned(23 downto 0);
        variable shift : integer;
        variable diff : signed(24 downto 0);
        variable norm_shift : integer;
        variable temp_frac : unsigned(22 downto 0);
        variable effective_sign_b : std_logic;
        variable aligned_small : unsigned(23 downto 0);
        variable unsigned_diff : unsigned(24 downto 0);
        -- Division variables
        variable q : unsigned(23 downto 0);
        variable r : unsigned(47 downto 0);
        variable d : unsigned(47 downto 0);
        variable i : integer;
        variable sign_res2 : std_logic;
        variable exp_res_int : integer;
        variable final_frac : unsigned(22 downto 0);
    begin
        if rst = '1' then
            result_reg <= (others => '0');
            ready_reg <= '0';
        elsif rising_edge(clk) then
            ready_reg <= '0';
            sign_a := get_sign(a);
            sign_b := get_sign(b);
            exp_a := get_exp(a);
            exp_b := get_exp(b);
            frac_a := get_frac(a);
            frac_b := get_frac(b);
            special_ready := '0';
            special_out := (others => '0');
            if is_nan(exp_a, frac_a) then
                special_out := a; special_ready := '1';
            elsif is_nan(exp_b, frac_b) then
                special_out := b; special_ready := '1';
            elsif is_inf(exp_a, frac_a) and is_inf(exp_b, frac_b) then
                -- Inf - Inf => NaN
                if op = "00" then -- SUB
                    if sign_a = sign_b then
                        special_out := x"7FC00000"; -- qNaN (positive)
                    else
                        -- Inf - (-Inf) = Inf + Inf -> Inf (sign depends)
                        special_out := a;
                    end if;
                elsif op = "01" then -- DIV
                    special_out := x"7FC00000"; -- NaN
                end if;
                special_ready := '1';
            elsif is_inf(exp_a, frac_a) then
                -- Inf op finite
                if op = "00" then -- SUB: Inf - finite = Inf
                    special_out := a; special_ready := '1';
                elsif op = "01" then -- DIV: Inf / finite = Inf (sign)
                    special_out := a; special_ready := '1';
                end if;
            elsif is_inf(exp_b, frac_b) then
                if op = "00" then
                    -- finite - Inf = -Inf (sign opposite)
                    special_out := (sign_b xor '1') & std_logic_vector(exp_b) & std_logic_vector(frac_b);
                    special_ready := '1';
                elsif op = "01" then
                    -- finite / Inf = 0
                    special_out := (others => '0'); special_out(31) := sign_a xor sign_b; special_ready := '1';
                end if;
            elsif is_zero(exp_b, frac_b) and op = "01" then
                -- divide by zero
                if is_zero(exp_a, frac_a) then
                    -- 0 / 0 => NaN
                    special_out := x"7FC00000"; special_ready := '1';
                else
                    -- finite / 0 => Inf (with sign)
                    special_out := pack_fp(sign_a xor sign_b, x"FF", (22 downto 0 => '0')); special_ready := '1';
                end if;
            elsif is_zero(exp_a, frac_a) and op = "01" then
                -- 0 / finite = 0
                special_out := (others => '0'); special_out(31) := sign_a xor sign_b; special_ready := '1';
            end if;

            if special_ready = '1' then
                result_reg <= special_out;
                ready_reg <= '1';
            else
                -- build mantissas
                if exp_a = x"00" then
                    mant_a := "0" & frac_a; -- denormal
                else
                    mant_a := "1" & frac_a;
                end if;
                if exp_b = x"00" then
                    mant_b := "0" & frac_b;
                else
                    mant_b := "1" & frac_b;
                end if;

                if op = "00" then
                    -- A - B = A + (-B)
                    effective_sign_b := not sign_b;
                    
                    if sign_a = effective_sign_b then
                        sign_res := sign_a;
                        if exp_a >= exp_b then
                            exp_large := exp_a;
                            shift := to_integer(exp_a - exp_b);
                            aligned_small := mant_b;
                            if shift > 0 and shift <= 24 then
                                aligned_small := shift_right(mant_b, shift);
                            end if;
                            unsigned_diff := ('0' & mant_a) + ('0' & aligned_small);
                        else
                            exp_large := exp_b;
                            shift := to_integer(exp_b - exp_a);
                            aligned_small := mant_a;
                            if shift > 0 and shift <= 24 then
                                aligned_small := shift_right(mant_a, shift);
                            end if;
                            unsigned_diff := ('0' & mant_b) + ('0' & aligned_small);
                        end if;
                        if unsigned_diff(24) = '1' then
                            unsigned_diff := '0' & unsigned_diff(24 downto 1);
                            res_exp := to_integer(exp_large) + 1;
                            norm_shift := 0;
                        else
                            res_exp := to_integer(exp_large);
                            norm_shift := 0;
                        end if;
                    else
                        if exp_a > exp_b then
                            exp_large := exp_a; mant_large := mant_a; 
                            exp_small := exp_b; mant_small := mant_b; 
                            sign_res := sign_a;
                        elsif exp_a < exp_b then
                            exp_large := exp_b; mant_large := mant_b; 
                            exp_small := exp_a; mant_small := mant_a; 
                            sign_res := effective_sign_b;
                        else
                            if mant_a >= mant_b then
                                exp_large := exp_a; mant_large := mant_a; 
                                mant_small := mant_b; 
                                sign_res := sign_a;
                            else
                                exp_large := exp_b; mant_large := mant_b; 
                                mant_small := mant_a; 
                                sign_res := effective_sign_b;
                            end if;
                            exp_small := exp_a;
                        end if;
                        shift := to_integer(exp_large - exp_small);
                        if shift > 24 then
                            diff := signed('0' & std_logic_vector(mant_large));
                        else
                            aligned_small := mant_small;
                            if shift > 0 then
                                aligned_small := shift_right(mant_small, shift);
                            end if;
                            diff := signed('0' & std_logic_vector(mant_large)) - signed('0' & std_logic_vector(aligned_small));
                        end if;
                        unsigned_diff := unsigned(std_logic_vector(diff));
                        res_exp := to_integer(exp_large);
                        norm_shift := 0;
                    end if;
                    if unsigned_diff = 0 then
                        result_reg <= (others => '0');
                        ready_reg <= '1';
                    else
                        while norm_shift < 24 and unsigned_diff(23) = '0' loop
                            unsigned_diff := unsigned_diff(23 downto 0) & '0';
                            norm_shift := norm_shift + 1;
                        end loop;
                        res_exp := res_exp - norm_shift;
                        temp_frac := unsigned_diff(22 downto 0);
                        if res_exp <= 0 then
                            result_reg <= (others => '0');
                        else
                            result_reg <= pack_fp(sign_res, to_unsigned(res_exp,8), temp_frac);
                        end if;
                        ready_reg <= '1';
                    end if;

                elsif op = "01" then
                    sign_res2 := sign_a xor sign_b;
                    exp_res_int := to_integer(exp_a) - to_integer(exp_b) + BIAS;
                    d := (47 downto 0 => '0');
                    d(47 downto 24) := mant_b;
                    r := (47 downto 0 => '0');
                    r(46 downto 23) := mant_a;
                    q := (23 downto 0 => '0');

                    for i in 0 to 23 loop
                        r := r(46 downto 0) & '0';
                        if r >= d then
                            r := r - d;
                            q(23 - i) := '1';
                        end if;
                    end loop;
                    if q(23) = '0' then
                        q := shift_left(q, 1);
                        exp_res_int := exp_res_int - 1;
                    end if;

                    if exp_res_int <= 0 then
                        result_reg <= (others => '0');
                        ready_reg <= '1';
                    elsif exp_res_int >= 255 then
                        result_reg <= pack_fp(sign_res2, x"FF", (22 downto 0 => '0'));
                        ready_reg <= '1';
                    else
                        final_frac := q(22 downto 0);
                        result_reg <= pack_fp(sign_res2, to_unsigned(exp_res_int,8), final_frac);
                        ready_reg <= '1';
                    end if;

                else
                    result_reg <= (others => '0');
                    ready_reg <= '1';
                end if;
            end if;
        end if;
    end process;
    rdy <= ready_reg;
    y <= result_reg;
end architecture rtl;
