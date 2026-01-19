--!@file DetectorInterface.vhd
--!@brief Instantiate the Data_Builder.vhd and the multiAdcPlaneInterface.vhd
--!@details Top to interconnect all of the u-strip-related modules
--!@author Mattia Barbanera (mattia.barbanera@infn.it)
--!@author Keida Kanxheri (keida.kanxheri@pg.infn.it)
--!@author Stefan Frentescu, stefan.frentescu@studenti.unipg.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;

use work.basic_package.all;
use work.paperoPackage.all;


--!@copydoc DetectorInterface.vhd
entity DetectorInterface is
  generic(
    pFASTDATA_WIDTH     : natural := 32
  );
  port (
    iCLK            : in  std_logic;    --!Main clock
    iRST            : in  std_logic;    --!Main reset
    -- Controls
    iCNT            : in  tControlIn;     --!Enable
    iTRIG           : in  std_logic;       --!Trigger
    oCNT            : out tControlOUT;     --!Control signals in output
    iEXTEND_BUSY    : in  std_logic_vector(15 downto 0);
    -- FastDATA Interface
    
    oFASTDATA       : out tFifoFdiIn;
    iFASTDATA       : in  tFifoFdiOut
    );
end DetectorInterface;

--!@copydoc DetectorInterface.vhd
architecture std of DetectorInterface is
  --State
  type tState is (IDLE, RESET, RUN, COMPL);
  signal sState, sNextState : tState := IDLE;
  signal sCompl : std_logic := '0';

  --Plane interface
  signal sCntOut       : tControlOut;
  signal sCntIn        : tControlIn;

  --Busy Extend
  signal sExtendBusy     : std_logic;

  --Signal
  signal sFifoIn  : tFifoFdiIn;
  signal sFifoOut : tFifoFdiOut;

    -- Parameters
  constant cNumDetector : integer := 2;
  constant cNumAdc      : integer := 10;
  constant cNumChannels : integer := 128;

   -- Signals per generatore
  signal sAdcIndex  : std_logic_vector(ceil_log2(cNumAdc/cNumDetector)-1 downto 0);
  signal sChannel    : std_logic_vector(cFIFO_WIDTH-1 downto 0);

  signal sAdcValue1,sAdcValue2 : std_logic_vector(cFIFO_WIDTH-1 downto 0);

  


begin

  sCntIn.en     <= iCNT.en;
  sCntIn.start  <= iTRIG;

  sFifoOut.aEmpty <= iFASTDATA.aEmpty;
  sFifoOut.empty  <= iFASTDATA.empty;
  sFifoOut.aFull  <= iFASTDATA.aFull;
  sFifoOut.full   <= iFASTDATA.full;

  -- impacchetta come nel priorityEncoder: word1 & word2
  sFifoIn.data <=  sAdcValue1(13 downto 0) & "00" & sAdcValue2(13 downto 0) & "00";
  oFASTDATA.data <= sFifoIn.data;
  oFASTDATA.wr <= sFifoIn.wr;
  oFASTDATA.rd <= sFifoIn.rd;

  oCNT.busy  <= sCntOut.busy or sExtendBusy;
  oCNT.error <= sCntOut.error;
  oCNT.reset <= sCntOut.reset;
  oCNT.compl <= sCntOut.compl;

  --!@brief Extend busy from [320 ns, ~20 ms], in multiples of 320 ns
  busy_extend : delay_timer
    generic map(
      pWIDTH => 20
    )
    port map(
      iCLK   => iCLK,
      iRST   => iRST,
      iSTART => sCompl,
      iDELAY => iEXTEND_BUSY & "0000",
      oBUSY  => sExtendBusy,
      oOUT   => open
      );

  state_reg : process(iCLK)
    begin
      if rising_edge(iCLK) then
        if iRST = '1' then
          sState <= RESET;
        else
          sState <= sNextState;
        end if;
      end if;
    end process;

  state_next : process(sState, sCntIn.en, sCntIn.start, sCompl, sCntOut.busy, sExtendBusy)
  begin
    case sState is

      when IDLE =>
        if (sCntIn.en = '1' and sCntIn.start = '1') then
          sNextState <= RUN;
        else 
          sNextState <= IDLE;
        end if;

      when RESET =>
        sNextState <= IDLE;

      when RUN =>
        if sCompl = '1' then
          sNextState <= COMPL;
        else 
          sNextState <= RUN;
        end if;

      when COMPL =>
        if (sCntOut.busy = '1' or sExtendBusy = '1') then
          sNextState <= COMPL;
        else
          sNextState <= IDLE;
        end if;

      when others =>
        sNextState <= RESET;

    end case;
  end process;

sFifoIn.rd <= '0'; --not used
datapath : process(iCLK)
  variable vFifoReady : std_logic;
  begin
    if rising_edge(iCLK) then
      if iRST = '1' then
        sAdcIndex  <= (others=>'0');
        sChannel   <= (others=>'0');
        sCompl <= '0';
        sFifoIn.wr   <= '0';
        sCntOut.reset <= '1';
        sCntOut.error <= '0';
        sCntOut.compl <= '0';
        sCntOut.busy  <= '1';
      else
        sAdcIndex <= (others=>'0');
        sFifoIn.wr <= '0';  -- la metto di default uguale a 0
        sCompl <= '0';

        sCntOut.reset <= '0';
        sCntOut.error <= '0';
        sCntOut.compl <= '0';

        vFifoReady := not sFifoOut.aFull;
        -- calcola il valore del canale dell'ADC corrente:
        -- ogni ADC ha 128 valori consecutivi
        sAdcValue1 <= (slv2int(sAdcIndex)*cNumDetector)*cNumChannels + sChannel;
        sAdcValue2 <= (slv2int(sAdcIndex)*cNumDetector+1)*cNumChannels + sChannel;

        case sState is
          when RESET =>
            sCntOut.reset <= '1';
            sCntOut.busy  <= '1';
            sChannel   <= (others=>'0');

          when IDLE =>
            sChannel   <= (others=>'0');
            sCntOut.busy  <= '0';
          
          when RUN =>
            sCntOut.busy  <= '1';
            --sAdcValue1 <= (slv2int(sAdcIndex)*cNumDetector)*cNumChannels + sChannel;
            --sAdcValue2 <= (slv2int(sAdcIndex)*cNumDetector+1)*cNumChannels + sChannel;
            
            if sFifoOut.aFull = '0' then
              sFifoIn.wr   <= vFifoReady;  -- scrittura valida
            end if;
            -- faccio si che i dati che genero siano sempre compresi nei limiti dei canali giusti
            if sAdcIndex < (cNumAdc/cNumDetector)-1 then
              sAdcIndex <= sAdcIndex + vFifoReady;
            else
              sAdcIndex <= (others => '0');
              sChannel <= sChannel + vFifoReady; --Aggiungo 1 solo quando ho finito gli ADC
            end if;
            
            if (sAdcIndex = (cNumAdc/cNumDetector)-2) and (sChannel = cNumChannels-1) then
              sCompl <= '1';
            end if;
            
          when COMPL =>
            sChannel   <= (others=>'0');
            sCntOut.compl <= '1';
            sCntOut.busy  <= '0';

          when others =>
            sChannel   <= (others=>'0');
            sCntOut.busy  <= '1';
            sCntOut.error <= '1';
        
          end case;
        end if;
      end if;
end process;


end architecture std;
