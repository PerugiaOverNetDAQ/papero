--!@file trigBusyLogic.vhd
--!@brief Trigger and Busy logic
--!@details
--!
--!Generate the trigger signal, wheter from the internal counter or the external
--! pin. Count all the triggers and the trigger occurred when busy is asserted.
--!Generate the busy signal.
--!
--!@author Mattia Barbanera, mattia.barbanera@infn.it
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.basic_package.all;
use work.paperoPackage.all;

--!@copydoc trigBusyLogic.vhd
entity trigBusyLogic is
  port(
    iCLK            : in  std_logic;    --!Clock (used at rising edge)
    iRST            : in  std_logic;    --!Synchronous Reset
    iRST_COUNTERS   : in  std_logic;    --!Synchronous Reset for the counters
    iCFG            : in  std_logic_vector(31 downto 0);  --!Configuration
    iEXT_TRIG       : in  std_logic;    --!External Trigger
    iBUSIES_AND     : in  std_logic_vector(7 downto 0);  --!Busy signals and'ed
    iBUSIES_OR      : in  std_logic_vector(7 downto 0);  --!Busy signals or'ed
    oTRIG           : out std_logic;    --!Output trigger
    oTRIG_ID        : out std_logic_vector(15 downto 0);  --!Trigger type
    oTRIG_COUNT     : out std_logic_vector(31 downto 0);  --!Total Trigger number
    oEXT_TRIG_COUNT : out std_logic_vector(31 downto 0);  --!External Trigger number
    oINT_TRIG_COUNT : out std_logic_vector(31 downto 0);  --!Internal Trigger number
    oTRIG_WHEN_BUSY : out std_logic_vector(7 downto 0);  --!Triggers occurred when system is busy
    oBUSY           : out std_logic     --!Output busy
    );
end entity trigBusyLogic;

--!@todo sTotTrigNum computed with a synchronous process
--!@copydoc trigBusyLogic.vhd
architecture std of trigBusyLogic is

  signal sIntTrig       : std_logic;
  signal sIntTrigEn     : std_logic;
  signal sTrigCounter   : std_logic_vector(31 downto 0);
  signal sIntTrigPeriod : std_logic_vector(31 downto 0);

  signal sPhysCalibn : std_logic;

  signal sTrig     : std_logic;
  signal sTrigWhenBusy : std_logic;
  signal sMainTrigExt : std_logic;
  signal sMainTrigInt : std_logic;
  signal sTrigId   : std_logic_vector(15 downto 0);
  signal sExtTrigNum : std_logic_vector(oEXT_TRIG_COUNT'length-2 downto 0);
  signal sIntTrigNum : std_logic_vector(oINT_TRIG_COUNT'length-2 downto 0);
  signal sTotTrigNum : std_logic_vector(oTRIG_COUNT'length-1 downto 0);

  signal sBusy : std_logic;

begin
  -- Combinatorial assignments ------------------------------------------------
  oTRIG    <= sTrig;
  oBUSY    <= sBusy;
  oTRIG_ID <= sTrigId;

  sIntTrigEn     <= iCFG(0);
  sPhysCalibn    <= iCFG(1);
  sIntTrigPeriod <= iCFG(iCFG'left downto 4) & "0000";

  sTrig <= sMainTrigInt when sIntTrigEn = '1' else sMainTrigExt;
  sTrigWhenBusy <= (iEXT_TRIG or sIntTrig) and sBusy;
  sMainTrigExt <= iEXT_TRIG and not sBusy;
  sMainTrigInt <= sIntTrig and not sBusy;

  sTotTrigNum <= ('0' & sExtTrigNum) + ('0' & sIntTrigNum);
  oTRIG_COUNT     <= sTotTrigNum;
  oEXT_TRIG_COUNT <= '0' & sExtTrigNum;
  oINT_TRIG_COUNT <= '0' & sIntTrigNum;

  sTrigId <= cTRG_PHYS_INT  when (sIntTrigEn = '1' and sPhysCalibn = '1') else
             cTRG_CALIB_INT when (sIntTrigEn = '1' and sPhysCalibn = '0') else
             cTRG_CALIB_EXT when (sIntTrigEn = '0' and sPhysCalibn = '1') else
             cTRG_PHYS_EXT;--  when (sIntTrigEn = '0' and sPhysCalibn = '0');

  sBusy <= unary_and(iBUSIES_AND) or unary_or(iBUSIES_OR) or iRST;
  -----------------------------------------------------------------------------

  --!@brief Internal trigger counter
  --!@param[in] iCLK  Clock, used on rising edge
  IntStart_proc : process (iCLK)
  begin
    CLK_IF_TRIG : if (rising_edge(iCLK)) then
      RST_IF_TRIG : if (iRST = '1') then
        sTrigCounter <= (others => '0');
        sIntTrig     <= '0';
      else
        if (sTrigCounter < sIntTrigPeriod) then
          sTrigCounter <= sTrigCounter + sIntTrigEn;
          sIntTrig     <= '0';
        else
          sTrigCounter <= (others => '0');
          sIntTrig     <= '1';
        end if;
      end if RST_IF_TRIG;
    end if CLK_IF_TRIG;
  end process IntStart_proc;

  --!@brief Actual external triggers counter
  EXT_TRIG_COUNTER : counter
    generic map (
      pOVERLAP  => "Y",
      pBUSWIDTH => oEXT_TRIG_COUNT'length-1
      )
    port map (
      iCLK   => iCLK,
      iRST   => iRST_COUNTERS,
      iEN    => sMainTrigExt,
      iLOAD  => '0',
      iDATA  => (others => '0'),
      oCOUNT => sExtTrigNum,
      oCARRY => open
      );

  --!@brief Actual internal triggers counter
  INT_TRIG_COUNTER : counter
    generic map (
      pOVERLAP  => "Y",
      pBUSWIDTH => oINT_TRIG_COUNT'length-1
      )
    port map (
      iCLK   => iCLK,
      iRST   => iRST_COUNTERS,
      iEN    => sMainTrigInt,
      iLOAD  => '0',
      iDATA  => (others => '0'),
      oCOUNT => sIntTrigNum,
      oCARRY => open
      );

  --!@brief Count the triggers occurred when busy is asserted
  TRIG_WHEN_BUSY_COUNTER : counter
    generic map (
      pOVERLAP  => "N",
      pBUSWIDTH => oTRIG_WHEN_BUSY'length
      )
    port map (
      iCLK   => iCLK,
      iRST   => iRST_COUNTERS,
      iEN    => sTrigWhenBusy,
      iLOAD  => '0',
      iDATA  => (others => '0'),
      oCOUNT => oTRIG_WHEN_BUSY,
      oCARRY => open
      );

end architecture std;
