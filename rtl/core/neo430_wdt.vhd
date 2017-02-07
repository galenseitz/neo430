-- #################################################################################################
-- #  << NEO430 - Watchdog Timer >>                                                                #
-- # ********************************************************************************************* #
-- #  Watchdog timer, generates a system wide reset when enabled and not timed out.                #
-- #  The internal counter is 16 bit wide and triggers the reset when overflowing. The clock       #
-- #  is selected via the clk_sel bits of the control register. The WDT can only operate when the  #
-- #  enable bit is set. A system wide reset can be generated at any time by setting the SYSRST    #
-- #  bit.                                                                                         #
-- #  Any write access to the WDT can only be performed, if the higher byte of the written data    #
-- #  contains the specific WDT password.                                                          #
-- # ********************************************************************************************* #
-- # This file is part of the NEO430 Processor project: http://opencores.org/project,neo430        #
-- # Copyright 2015-2017, Stephan Nolting: stnolting@gmail.com                                     #
-- #                                                                                               #
-- # This source file may be used and distributed without restriction provided that this copyright #
-- # statement is not removed from the file and that any derivative work contains the original     #
-- # copyright notice and the associated disclaimer.                                               #
-- #                                                                                               #
-- # This source file is free software; you can redistribute it and/or modify it under the terms   #
-- # of the GNU Lesser General Public License as published by the Free Software Foundation,        #
-- # either version 3 of the License, or (at your option) any later version.                       #
-- #                                                                                               #
-- # This source is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;      #
-- # without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     #
-- # See the GNU Lesser General Public License for more details.                                   #
-- #                                                                                               #
-- # You should have received a copy of the GNU Lesser General Public License along with this      #
-- # source; if not, download it from http://www.gnu.org/licenses/lgpl-3.0.en.html                 #
-- # ********************************************************************************************* #
-- #  Stephan Nolting, Hannover, Germany                                               20.12.2016  #
-- #################################################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.neo430_package.all;

entity neo430_wdt is
  port (
    -- host access --
    clk_i       : in  std_ulogic; -- global clock line
    rst_i       : in  std_ulogic; -- external reset, low-active, use as async
    rden_i      : in  std_ulogic; -- read enable
    wren_i      : in  std_ulogic_vector(01 downto 0); -- write enable
    addr_i      : in  std_ulogic_vector(15 downto 0); -- address
    data_i      : in  std_ulogic_vector(15 downto 0); -- data in
    data_o      : out std_ulogic_vector(15 downto 0); -- data out
    -- clock generator --
    clkgen_en_o : out std_ulogic; -- enable clock generator
    clkgen_i    : in  std_ulogic_vector(07 downto 0);
    -- system reset --
    rst_o       :  out std_ulogic  -- timeout reset, low_active, use as async
  );
end neo430_wdt;

architecture neo430_wdt_rtl of neo430_wdt is

  -- IO space: module base address --
  constant hi_abb_c : natural := index_size(io_size_c)-1; -- high address boundary bit
  constant lo_abb_c : natural := index_size(wdt_size_c); -- low address boundary bit

  -- Watchdog access password - do not change! --
  constant wdt_password_c : std_ulogic_vector(07 downto 0) := x"47";

  -- Control register bits --
  constant ctrl_clksel0_c : natural := 0; -- r/w: prescaler select bit 0
  constant ctrl_clksel1_c : natural := 1; -- r/w: prescaler select bit 1
  constant ctrl_clksel2_c : natural := 2; -- r/w: prescaler select bit 2
  constant ctrl_enable_c  : natural := 3; -- r/w: WDT enable
  constant ctrl_rcause_c  : natural := 4; -- r/-: reset cause (0: external, 1: watchdog timeout)
  constant ctrl_sysrst_c  : natural := 5; -- -/w: set one to generate system hardware reset

  -- access control --
  signal acc_en : std_ulogic; -- module access enable
  signal pwd_ok : std_ulogic; -- password correct
  signal wren   : std_ulogic;

  -- accessible regs --
  signal source  : std_ulogic; -- source of the system reset: '0' = external, '1' = watchdog timeout
  signal enable  : std_ulogic;
  signal clk_sel : std_ulogic_vector(02 downto 0);

  -- reset counter --
  signal cnt      : std_ulogic_vector(16 downto 0);
  signal usr_rst  : std_ulogic;
  signal rst_gen  : std_ulogic_vector(03 downto 0);
  signal rst_sync : std_ulogic_vector(01 downto 0);

  -- prescaler clock generator --
  signal prsc_tick, prsc_sel, prsc_sel_ff : std_ulogic;

begin

  -- Access Control -----------------------------------------------------------
  -- -----------------------------------------------------------------------------
  acc_en <= '1' when (addr_i(hi_abb_c downto lo_abb_c) = wdt_base_c(hi_abb_c downto lo_abb_c)) else '0';
  pwd_ok <= '1' when (data_i(15 downto 8) = wdt_password_c) else '0'; -- password check
  wren   <= '1' when ((acc_en = '1') and (wren_i = "11") and (pwd_ok = '1')) else '0';


  -- Write Access, Reset Generator --------------------------------------------
  -- -----------------------------------------------------------------------------
  wdt_core: process(rst_i, rst_sync(1), clk_i)
  begin
    if (rst_i = '0') or (rst_sync(1) = '0') then -- external or internal reset
      enable  <= '0'; -- disable WDT
      clk_sel <= (others => '1'); -- slowest clock source
      rst_gen <= (others => '1'); -- do NOT fire on reset!
    elsif rising_edge(clk_i) then
      -- allow write if password is correct
      if (wren = '1') then
        enable  <= data_i(ctrl_enable_c);
        clk_sel <= data_i(ctrl_clksel2_c downto ctrl_clksel0_c);
      end if;
      -- reset generator --
      if ((enable = '1') and (cnt(cnt'left) = '1')) or (usr_rst = '1') then
        rst_gen <= (others => '0');
      else
        rst_gen <= rst_gen(rst_gen'left-1 downto 0) & '1';
      end if;
    end if;
  end process wdt_core;

  -- manual reset --
  usr_rst <= wren and data_i(ctrl_sysrst_c);


  -- Counter Update -----------------------------------------------------------
  -- -----------------------------------------------------------------------------
  cnt_sync: process(clk_i)
  begin
    if rising_edge(clk_i) then
      -- reset synchronizer --
      rst_sync <= rst_sync(0) & rst_gen(rst_gen'left);
      -- tick generator --
      prsc_sel_ff <= prsc_sel;
      -- counter update --
      if (wren = '1') then -- clear counter on write access (manual watchdog reset)
        cnt <= (others => '0');
      elsif (enable = '1') and (prsc_tick = '1') then
        cnt <= std_ulogic_vector(unsigned('0' & cnt(cnt'left-1 downto 0)) + 1);
      end if;
    end if;
  end process cnt_sync;

  -- counter clock select / edge detection --
  clkgen_en_o <= enable;
  prsc_sel    <= clkgen_i(to_integer(unsigned(clk_sel)));
  prsc_tick   <= prsc_sel_ff and (not prsc_sel); -- edge detector

  -- system reset --
  rst_o <= rst_sync(1);


  -- Reset Cause Indicator ----------------------------------------------------
  -- -----------------------------------------------------------------------------
  rst_cause: process(rst_i, clk_i)
  begin
    if (rst_i = '0') then
      source <= '0';
    elsif rising_edge(clk_i) then
      source <= source or (not rst_sync(1));
    end if;
  end process rst_cause;


  -- Read Access --------------------------------------------------------------
  -- -----------------------------------------------------------------------------
  read_access: process(clk_i)
  begin
    if rising_edge(clk_i) then
      data_o <= (others => '0');
      if (acc_en = '1') and (rden_i = '1') then
        data_o(ctrl_clksel2_c downto ctrl_clksel0_c) <= clk_sel;
        data_o(ctrl_enable_c) <= enable;
        data_o(ctrl_rcause_c) <= source;
      end if;
    end if;
  end process read_access;


end neo430_wdt_rtl;
