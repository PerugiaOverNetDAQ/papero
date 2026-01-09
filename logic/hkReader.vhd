--!@file hkReader.vhd
--!@brief Readout of the housekeeping registers
--!@details
--!
--!Read the registers periodically and send the packet formatted as in
--! PAPERO_formats.xlsx: \n
--!
--! | Abbr  | Description | Default |
--! |-------|-------------|---------|
--! |SoP | Start-of-Packet | x"55AADEAD" |
--! |Len | Length | Number of 32-bit payload words + 5 |
--! |Ver | Firmware Version | - |
--! |Hdr | Fixed hader | x"4EADE500" |
--! |    | Register Content | - |
--! |    | [31:24] parity bits, [15:0] Register Address | - |
--! |    | ................ | - |
--! |Trl | Trailer | x"600DF00D" |
--! |CRC | CRC-32 | - |
--!
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;

use work.basic_package.all;
use work.paperoPackage.all;

--!@copydoc hkReader.vhd
entity hkReader is
  generic(
    pFIFO_WIDTH : natural := 32;        --!FIFO data width
    pPARITY     : string  := "EVEN";    --!Parity polarity ("EVEN" or "ODD")
    pGW_VER     : std_logic_vector(31 downto 0)  --!Firmware version from HoG
    );
  port (
    iCLK        : in  std_logic;        --!Main clock
    iRST        : in  std_logic;        --!Main reset
    iCNT        : in  tControlIn;       --!Control input signals
    oCNT        : out tControlOut;      --!Control output flags
    iINT_START  : in  std_logic;        --!Enable for the internal start
    --Register array
    iREG_ARRAY  : in  tRegArray;        --!Register array input
    --Output FIFO interface
    oFIFO_DATA  : out std_logic_vector(pFIFO_WIDTH-1 downto 0);  --!Fifo Data in
    oFIFO_WR    : out std_logic;        --!Fifo write-request in
    iFIFO_AFULL : in  std_logic         --!Fifo almost-full flag
    );
end entity hkReader;

--!@copydoc hkReader.vhd
architecture std of hkReader is
  -- Constants -----------------------------------------------------------------
  --!Packet length: 2*Number of registers + header + trailer
  constant cPKT_LEN : natural := (cHPS_REGISTERS * 2) + 5;

  -- Signals -------------------------------------------------------------------
  --FSM
  type tHkStatus is (IDLE, WAIT_FOR_FIFO, SOP, LEN, FW_VER, HDR,
                     REGISTER_CONTENT, REGISTER_ADDRESS, EOP, CRC);
  signal sHkState  : tHkStatus;
  signal sFsmError : std_logic;

  --Output FIFO
  signal sFifoData : std_logic_vector(pFIFO_WIDTH-1 downto 0);
  signal sFifoWr   : std_logic;

  --Register counter
  signal sRegCounter : natural range 0 to (cHPS_REGISTERS-1);

  --Internal Start
  signal sStartCounter : std_logic_vector(31 downto 0);
  signal sStart        : std_logic;
  signal sExtStartRE   : std_logic;

  --Parity
  signal sParity : std_logic_vector(3 downto 0);

  --CRC32
  signal sCrc : tCrc32;

begin
  oFIFO_DATA <= sFifoData;
  oFIFO_WR   <= sFifoWr;

  --!@brief Rising edge of the start signal
  start_re : edge_detector
    port map (
      iCLK    => iCLK,
      iRST    => '0',
      iD      => iCNT.start,
      oEDGE_R => sExtStartRE
      );

  --!@brief FSM to send an HK packet. A-full is checked only at the beginning.
  --!@param[in] iCLK Clock, used on rising edge
  --!@return sHkState Next state of the FSM
  --!@return sFifoData Data to be written to the output FIFO
  --!@return sFifoWr Write-request to the FIFO
  --!@todo can remove WAIT_FOR_FIFO waiting in case FIFO is not a-full
  --!@todo What if the address is greater than the maximum allowable?
  --!@todo What if a start comes when busy?
  hkStateFSM_proc : process (iCLK)
    variable vAddrParity : std_logic_vector(1 downto 0);
  begin
    CLKIF : if (rising_edge(iCLK)) then
      RST_EN_IF : if (iRST = '1') then
        sFsmError   <= '0';
        sRegCounter <= 0;
        sFifoWr     <= '0';
        sFifoData   <= (others => '0');
        sParity     <= (others => '0');
        sHkState    <= IDLE;

      elsif (iCNT.en = '1') then
        --default values, to be overwritten when necessary
        sRegCounter <= 0;
        sFifoWr     <= '1';
        sFifoData   <= (others => '0');
        sParity     <= (others => '0');
        case (sHkState) is
          --Wait for a start and check if
          when IDLE =>
            sFifoWr <= '0';
            START_IF : if (sExtStartRE = '1' or sStart = '1') then
              sHkState <= WAIT_FOR_FIFO;
            end if START_IF;

          --Wait until the FIFO is not almost-full
          when WAIT_FOR_FIFO =>
            sFifoWr <= '0';
            WAIT_AFULL_IF : if iFIFO_AFULL = '1' then
              sHkState <= WAIT_FOR_FIFO;
            else
              sHkState <= SOP;
            end if WAIT_AFULL_IF;

          --Send the Start-of-Packet word
          when SOP =>
            sFifoData <= cF2H_HK_SOP;
            sHkState  <= LEN;

          --Send the length word
          when LEN =>
            sFifoData <= int2slv(cPKT_LEN, sFifoData'length);
            sHkState  <= FW_VER;

          --Send the hog firmware version word
          when FW_VER =>
            sFifoData <= pGW_VER;
            sHkState  <= HDR;

          --Send the header word
          when HDR =>
            sFifoData <= cF2H_HK_HDR;
            sHkState  <= REGISTER_CONTENT;

          --Send the content of the registers
          when REGISTER_CONTENT =>
            sRegCounter <= sRegCounter;
            sFifoData   <= iREG_ARRAY(sRegCounter);
            sHkState    <= REGISTER_ADDRESS;
            sParity(0) <= parity8bit(pPARITY,
                                     iREG_ARRAY(sRegCounter)(7 downto 0));
            sParity(1) <= parity8bit(pPARITY,
                                     iREG_ARRAY(sRegCounter)(15 downto 8));
            sParity(2) <= parity8bit(pPARITY,
                                     iREG_ARRAY(sRegCounter)(23 downto 16));
            sParity(3) <= parity8bit(pPARITY,
                                     iREG_ARRAY(sRegCounter)(31 downto 24));

          --Send the address of the registers and check if completed
          when REGISTER_ADDRESS =>
            vAddrParity(0) := parity8bit(pPARITY,
                                         int2slv(sRegCounter, 16)(7 downto 0));
            vAddrParity(1) := parity8bit(pPARITY,
                                         int2slv(sRegCounter, 16)(15 downto 8));
            sFifoData <= "00" & vAddrParity & sParity & x"00"
                         & int2slv(sRegCounter, 16);
            END_REG_IF : if (sRegCounter < cREGISTERS-1) then
              sRegCounter <= sRegCounter + 1;
              sHkState    <= REGISTER_CONTENT;
            else
              sRegCounter <= 0;
              sHkState    <= EOP;
            end if END_REG_IF;

          --Send the End-of-Packet word
          when EOP =>
            sFifoData <= cF2H_HK_EOP;
            sHkState  <= CRC;

          --Send the CRC word
          when CRC =>
            sFifoData <= sCrc.crc;
            sHkState  <= IDLE;

          --State not foreseen
          when others =>
            sFifoWr   <= '0';
            sFsmError <= '1';           --Reset only with a reset
            sHkState  <= IDLE;

        end case;
      end if RST_EN_IF;
    end if CLKIF;
  end process hkStateFSM_proc;

  --oCNT Assignment
  oCNT.busy <= '1'when sHkState /= IDLE else
               '0';
  oCNT.error <= sFsmError;
  oCNT.reset <= '1' when iRST = '1' else
                '0';
  oCNT.compl <= '1'when sHkState = CRC else
                '0';

  --!@brief Internal periodic start
  --!@param[in] iCLK  Clock, used on rising edge
  IntStart_proc : process (iCLK)
  begin
    CLK_IF_START : if (rising_edge(iCLK)) then
      RST_IF_START : if (iRST = '1') then
        sStartCounter <= (others => '0');
        sStart        <= '0';
      elsif (iCNT.en = '1') then
        if (sStartCounter < int2slv(cF2H_HK_PERIOD-1, sStartCounter'length)) then
          sStartCounter <= sStartCounter + iINT_START;
          sStart        <= '0';
        else
          sStartCounter <= (others => '0');
          sStart        <= '1';
        end if;
      end if RST_IF_START;
    end if CLK_IF_START;
  end process IntStart_proc;

  sCrc.rst <= '1' when sHkState = IDLE else
              '0';
  sCrc.en <= sFifoWr when sHkState = HDR
             or sHkState = REGISTER_CONTENT
             or sHkState = REGISTER_ADDRESS
             or sHkState = EOP else
             '0';
  sCrc.data <= sFifoData;
  --!Compute the CRC32 for packet content (except for SoP, Len, and EoP)
  CRC32_compute : CRC32
    generic map (
      pINITIAL_VAL => x"FFFFFFFF"
    )
    port map (
      iCLK    => iCLK,
      iRST    => sCrc.rst,
      iCRC_EN => sCrc.en,
      iDATA   => sCrc.data,
      oCRC    => sCrc.crc
      );


end architecture std;
