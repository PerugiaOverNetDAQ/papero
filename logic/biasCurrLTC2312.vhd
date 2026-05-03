--!@file biasCurrLTC2312.vhd
--!@brief Low-level SPI interface for multiple LTC2312-12 ADCs
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;

use work.basic_package.all;
use work.paperoPackage.all;

--!@copydoc biasCurrLTC2312.vhd
entity biasCurrLTC2312 is
  generic(
    pDEPTH : integer := 12;
    pADCS  : integer := 2
  );
  port(
    iCLK    : in  std_logic;            --!Main clock
    iRST    : in  std_logic;            --!Main reset
    -- control interface
    oBUSY   : out std_logic;            --!Converting
    oCOMPL  : out std_logic;            --!Done
    iEN     : in  std_logic;            --!Main enable
    iSTART  : in  std_logic;            --!Start conversion
    -- ADC SPI interface
    oCONV   : out std_logic;            --!ADCs start conversion
    oSCK    : out std_logic;            --!ADCs conversion clock
    iSDO    : in  std_logic_vector(pADCS - 1 downto 0); --!Serial data from ADCs
    -- Converted data in output
    oQ_CONV : out tLtc2312OutPort;      --!Output data
    oWR     : out std_logic
  );
end biasCurrLTC2312;

architecture std of biasCurrLTC2312 is
  constant cDIVIDER_WIDTH  : natural                                       := 16; --50%
  constant cDIVIDER_CYCLES : std_logic_vector(cDIVIDER_WIDTH - 1 downto 0) := int2slv(4,cDIVIDER_WIDTH); --12.5 MHz. MAX 20 MHz
  constant cDIVIDER_DUTY   : std_logic_vector(cDIVIDER_WIDTH - 1 downto 0) := int2slv(2,cDIVIDER_WIDTH); --50%

  type   tLtc2312Fsm   is (RESET, IDLE, SAMPLE, READOUT, LAST_CYCLE, WRITE_WORD);
  signal sLtc2312State : tLtc2312Fsm;

  --!@brief Wait for the enable assertion to change state
  --!@param[in] en  If '1', go to destination state
  --!@param[in] src Source state; remain here until enable is asserted
  --!@param[in] dst Destination state; go here when enable is asserted
  --!@return FSM next state depending on the enable assertion
  function wait4en(en : std_logic; src : tLtc2312Fsm; dst : tLtc2312Fsm)
  return tLtc2312Fsm is
    variable goto : tLtc2312Fsm;
  begin
    if (en = '1') then
      goto := dst;
    else
      goto := src;
    end if;
    return goto;
  end function wait4en;

  signal sSampleDuration : std_logic_vector(8 downto 0); --!Wait for minimum sample duration
  signal sRoBitNumber    : std_logic_vector(3 downto 0); --!Number of clock cycles sent to the LTC2312s
  signal sMultiSr        : tLtc2312OutPort; --!Shift register
  signal sQ              : tLtc2312OutPort; --!Output

  signal sDivRst  : std_logic;
  signal sDivEn   : std_logic;
  signal sDivClk  : std_logic;
  signal sDivEdge : std_logic;

  signal sStartConv : std_logic;

begin

  LTC2312_DIVIDER : clock_divider_2
    generic map(
      pPOLARITY => '0',
      pWIDTH    => cDIVIDER_WIDTH
    )
    port map(
      iCLK             => iCLK,
      iRST             => sDivRst,
      iEN              => sDivEn,
      iFREQ_DIV        => cDIVIDER_CYCLES,
      iDUTY_CYCLE      => cDIVIDER_DUTY,
      oCLK_OUT         => sDivClk,
      oCLK_OUT_RISING  => sDivEdge,
      oCLK_OUT_FALLING => open
    );

  -- Combinatorial assignments -------------------------------------------------
  sStartConv <= iSTART;
  oQ_CONV    <= sQ;

  ------------------------------------------------------------------------------

  --!@brief Combinatorial FSM to operate the ADC
  --!@param[in] iCLK Clock, used on rising edge
  --!@return sLtc2312State  FSM state
  --!@return 
  FSM_ADC_proc : process(iCLK)
  begin
    if (rising_edge(iCLK)) then
      if (iRST = '1') then
        oBUSY           <= '1';
        oSCK            <= '0';
        oCONV           <= '0';
        oCOMPL          <= '0';
        oWR             <= '0';
        sQ              <= (others => (others => '0'));
        sSampleDuration <= (others => '0');
        sRoBitNumber    <= (others => '0');
        sMultiSr        <= sMultiSr;
        sDivRst         <= '1';
        sDivEn          <= '0';
        sLtc2312State   <= RESET;
      else
        oBUSY           <= '1';
        oSCK            <= '0';
        oCONV           <= '0';
        oCOMPL          <= '0';
        oWR             <= '0';
        sQ              <= sQ;
        sSampleDuration <= (others => '0');
        sRoBitNumber    <= (others => '0');
        sMultiSr        <= sMultiSr;
        sDivRst         <= '1';
        sDivEn          <= '0';

        case (sLtc2312State) is
          --Reset the FSM
          when RESET =>
            sLtc2312State <= IDLE;

          --Wait for the start signal to be asserted
          when IDLE =>
            oBUSY <= '0';

            if (iEN = '1' and sStartConv = '1') then
              sLtc2312State <= SAMPLE;
            else
              sLtc2312State <= IDLE;
            end if;

          --Wait for the minimum duration of conversion, maintain oCONV high
          when SAMPLE =>
            oCONV           <= '1';
            sSampleDuration <= sSampleDuration + 1;

            if (sSampleDuration < int2slv((cLTC3213_CONV_CLK), sSampleDuration'length)) then
              sLtc2312State <= SAMPLE;
            else
              sLtc2312State <= READOUT;
            end if;

          --Read the incoming 12 bits in the SRs
          when READOUT =>
            oSCK         <= sDivClk;
            sRoBitNumber <= sRoBitNumber + sDivEdge; --Increment for each clock sent
            sDivRst      <= '0';
            sDivEn       <= '1';
            
            if (sDivEdge = '1') then
              SR_LOOP : for i in 0 to pADCS - 1 loop
                sMultiSr(i) <= sMultiSr(i)(pDEPTH - 2 downto 0) & iSDO(i); --Actual shift
              end loop SR_LOOP;
            end if;

            if (sRoBitNumber < int2slv((pDEPTH-1), sRoBitNumber'length)) then
              sLtc2312State <= READOUT;
            else
              sLtc2312State <= wait4en(sDivEdge, READOUT, LAST_CYCLE);
            end if;
          
          --Maintain clock in out, but don't shift
          when LAST_CYCLE =>
            oSCK         <= sDivClk;
            sDivRst      <= '0';
            sDivEn       <= '1';
            sLtc2312State <= wait4en(sDivEdge, LAST_CYCLE, WRITE_WORD);

          --Write the deserialized word in output
          when WRITE_WORD =>
            oCOMPL <= '1';
            oWR    <= '1';
            sQ     <= sMultiSr;

            sLtc2312State <= IDLE;

          --State not foreseen
          when others =>
            sLtc2312State <= RESET;

        end case;
      end if;                           --iRST
    end if;                             --iCLK
  end process FSM_ADC_proc;

end architecture std;
