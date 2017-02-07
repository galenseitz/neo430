-- #################################################################################################
-- #  << NEO430 - Data memory ("DMEM") >>                                                          #
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

entity neo430_dmem is
  port (
    clk_i  : in  std_ulogic; -- global clock line
    rden_i : in  std_ulogic; -- read enable
    wren_i : in  std_ulogic_vector(01 downto 0); -- write enable
    addr_i : in  std_ulogic_vector(15 downto 0); -- address
    data_i : in  std_ulogic_vector(15 downto 0); -- data in
    data_o : out std_ulogic_vector(15 downto 0)  -- data out
  );
end neo430_dmem;

architecture neo430_dmem_rtl of neo430_dmem is

  -- local signals --
  signal acc_en : std_ulogic;
  signal rdata  : std_ulogic_vector(15 downto 0);
  signal rden   : std_ulogic;
  signal addr   : natural range 0 to dmem_size_c/2-1;

  -- RAM --
  type dmem_file_t is array (0 to dmem_size_c/2-1) of std_ulogic_vector(15 downto 0);
  signal dmem_file : dmem_file_t;

  --- RAM attribute to inhibit bypass-logic - Altera only! ---
  attribute ramstyle : string;
  attribute ramstyle of dmem_file : signal is "no_rw_check";

begin

  -- Access Control -----------------------------------------------------------
  -- -----------------------------------------------------------------------------
  acc_en <= '1' when (addr_i >= dmem_base_c) and (addr_i < std_ulogic_vector(unsigned(dmem_base_c) + dmem_size_c)) else '0';
  addr <= to_integer(unsigned(addr_i(index_size(dmem_size_c/2) downto 1))); -- word aligned


  -- Memory Access ------------------------------------------------------------
  -- -----------------------------------------------------------------------------
  dmem_file_access: process(clk_i)
  begin
    if rising_edge(clk_i) then
      rden  <= rden_i and acc_en;
      if (acc_en = '1') and (wren_i(0) = '1') then -- write low byte
        dmem_file(addr)(07 downto 0) <= data_i(07 downto 0);
      end if;
      if (acc_en = '1') and (wren_i(1) = '1') then -- write high byte
        dmem_file(addr)(15 downto 8) <= data_i(15 downto 8);
      end if;
      rdata <= dmem_file(addr);
    end if;
  end process dmem_file_access;

  -- output gate --
  data_o <= rdata when (rden = '1') else x"0000";


end neo430_dmem_rtl;
