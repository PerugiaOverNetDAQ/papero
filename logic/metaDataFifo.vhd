--!@file metaDataFifo.vhd
--!brief Instantiation of several FIFOs for event metadata
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.paperoPackage.all;
use work.basic_package.all;

--!@copydoc metaDataFifo.vhd
entity metaDataFifo is
  generic (
    pFIFOs : natural := 9;
    pWIDTH : natural := 32
    );
  port (
    iCLK      : in  std_logic;
    iRST      : in  std_logic;
    oERR      : out std_logic;
    iRD       : in  std_logic;
    iWR       : in  std_logic;
    oEMPTY    : out std_logic;
    iMETADATA : in  tF2hMetadata;
    oMETADATA : out tF2hMetadata
    );
end entity;

--!@copydoc metaDataFifo.vhd
architecture std of metaDataFifo is
  signal sEmpty     : std_logic_vector(pFIFOs-1 downto 0);
  signal sFull      : std_logic_vector(pFIFOs-1 downto 0);
  signal sOverflow  : std_logic_vector(pFIFOs-1 downto 0);
  signal sUnderflow : std_logic_vector(pFIFOs-1 downto 0);

  type tMetaDataArray is array (0 to pFIFOs-1) of std_logic_vector(pWIDTH-1 downto 0);
  signal sData : tMetaDataArray;
  signal sQ    : tMetaDataArray;
begin

  sData(0)               <= iMETADATA.pktLen;
  sData(1)               <= iMETADATA.trigNum;
  sData(2)(31 downto 16) <= iMETADATA.detId;
  sData(2)(15 downto 0)  <= iMETADATA.trigId;
  sData(3)               <= iMETADATA.intTime(63 downto 32);
  sData(4)               <= iMETADATA.intTime(31 downto 0);
  sData(5)               <= iMETADATA.extTime(63 downto 32);
  sData(6)               <= iMETADATA.extTime(31 downto 0);
  sData(7)               <= iMETADATA.biasSet;
  sData(8)               <= iMETADATA.biasCur;

  oMETADATA.pktLen                <= sQ(0);
  oMETADATA.trigNum               <= sQ(1);
  oMETADATA.detId                 <= sQ(2)(31 downto 16);
  oMETADATA.trigId                <= sQ(2)(15 downto 0);
  oMETADATA.intTime(63 downto 32) <= sQ(3);
  oMETADATA.intTime(31 downto 0)  <= sQ(4);
  oMETADATA.extTime(63 downto 32) <= sQ(5);
  oMETADATA.extTime(31 downto 0)  <= sQ(6);
  oMETADATA.biasSet               <= sQ(7);
  oMETADATA.biasCur               <= sQ(8);

  oEMPTY <= sEmpty(0);
  --!@brief Generate multiple FIFOs to sample the metadata values
  METADATA_FIFO_GENERATE : for i in 0 to pFIFOs-1 generate
    sOverflow(i)  <= sFull(i) and iWR;
    sUnderflow(i) <= sEmpty(i) and iRD;

    METADATA_I_fifo : parametric_fifo_synch
      generic map(
        pWIDTH       => pWIDTH,
        pDEPTH       => ceil_log2(cFDI_DEPTH),
        pUSEDW_WIDTH => ceil_log2(ceil_log2(cFDI_DEPTH)),
        pAEMPTY_VAL  => 2,
        pAFULL_VAL   => ceil_log2(cFDI_DEPTH)-1,
        pSHOW_AHEAD  => "OFF"
        )
      port map(
        iCLK    => iCLK,
        iRST    => iRST,
        oUSEDW  => open,
        -- Write interface
        oAFULL  => open,
        oFULL   => sFull(i),
        iWR_REQ => iWR,
        iDATA   => sData(i),
        -- Read interface
        oAEMPTY => open,
        oEMPTY  => sEmpty(i),
        iRD_REQ => iRD,
        oQ      => sQ(i)
        );
  end generate METADATA_FIFO_GENERATE;

  ERROR_GEN_PROC : process(iCLK)
  begin
    if (rising_edge(iCLK)) then
      if (iRST = '1') then
        oERR <= '0';
      else
        if (unary_or(sUnderflow) = '1' or unary_or(sOverflow) = '1') then
          oERR <= '1';
        end if;
      end if;
    end if;
  end process ERROR_GEN_PROC;

end architecture;
