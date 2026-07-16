--!@file DetectorInterface.vhd
--!@brief Instantiate the Data_Builder.vhd and the multiAdcPlaneInterface.vhd
--!@details Top to interconnect all of the u-strip-related modules
--!@author Mattia Barbanera (mattia.barbanera@infn.it)
--!@author Keida Kanxheri (keida.kanxheri@pg.infn.it)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;

use work.basic_package.all;
use work.paperoPackage.all;
use work.FOOTpackage.all;

--!@copydoc DetectorInterface.vhd
entity DetectorInterface is
  port (
    iCLK            : in  std_logic;    --!Main clock
    iRST            : in  std_logic;    --!Main reset
    -- Controls
    iEN             : in  std_logic;    --!Enable
    iTRIG           : in  std_logic;    --!Trigger
    oCNT            : out tControlIntfOut;     --!Control signals in output
    iMSD_CONFIG     : in  msd_config;  --!Configuration from the control registers
    -- First FE-ADC chain ports
    oFE0            : out tFpga2FeIntf;        --!Output signals to the FE1
    oADC0           : out tFpga2AdcIntf;       --!Output signals to the ADC1
    -- Second FE-ADC chain ports
    oFE1            : out tFpga2FeIntf;        --!Output signals to the FE2
    oADC1           : out tFpga2AdcIntf;       --!Output signals to the ADC2
    -- ADCs Inputs
    iMULTI_ADC      : in  tMultiAdc2FpgaIntf;  --!Input signals from the ADCs
    -- FastDATA Interface
    oFASTDATA_DATA  : out std_logic_vector(cREG_WIDTH-1 downto 0);
    oFASTDATA_WE    : out std_logic;
    iFASTDATA_AFULL : in  std_logic;

    iSWITCH         : in std_logic_vector(3 downto 0);
    oLED            : out std_logic_vector(3 downto 0)
    );
end DetectorInterface;

--!@copydoc DetectorInterface.vhd
architecture std of DetectorInterface is
  --Plane interface
  signal sCntOut       : tControlIntfOut;
  signal sCntIn        : tControlIntfIn;
  signal sFeIn         : tFe2FpgaIntf;
  signal sMultiFifoOut : tMultiAdcFifoOut;
  signal sMultiFifoIn  : tMultiAdcFifoIn;

  --Trigger and busy
  signal sExtTrigDel     : std_logic;
  signal sExtTrigDelBusy : std_logic;
  signal sTrigDelBusy    : std_logic;
  signal sExtendBusy     : std_logic;

  --MSD Conifigurations
  signal sHpCfg : std_logic_vector (11 downto 0);
  signal sAdcFast : std_logic;

  signal sFastData_Data_LW  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sFastData_WE_LW    : std_logic;
  signal sFastData_Data_LW_RAW : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sFastData_WE_LW_RAW   : std_logic;
  signal sFastData_ADDR_LW_RAW   : std_logic_vector((ceil_log2(cTOTAL_ADCS * cADC_CHANNELS))-1 downto 0);
  signal sFastData_Data_LW_LSB : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sFastData_LW_HalfFull : std_logic;

  signal sFastData_Data_PE  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sFastData_WE_PE    : std_logic;

  signal sLW_WORD : t_FOOT_lef_data;
  signal sLW_PUTD : std_logic;

  signal sPedIn_Cal     : CalibCompIN;
  signal sPedOut_Cal    : CalibCompOUT;

  signal sSigRawIn_Cal  : CalibCompIN;
  signal sSigRawOut_Cal : CalibCompOUT;

  signal sSigIn_Cal     : CalibCompIN;
  signal sSigOut_Cal    : CalibCompOUT;

  signal sFlgIn_Cal     : CalibCompIN;
  signal sFlgOut_Cal    : CalibCompOUT;

  signal sLthOut_Cal    : CalibCompOUT;
  signal sHthOut_Cal    : CalibCompOUT;
  signal sRhtOut_Cal    : CalibCompOUT;

  signal sLW_Valid_ER   : std_logic;
  signal sLW_Clust_EN   : std_logic;

  -- CLUSTERING
  signal sClust_Read_Addr   : std_logic_vector((ceil_log2(cTOTAL_ADCS * cADC_CHANNELS))-1 downto 0);
  signal sClust_Read_Data   : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sClust_Read_En     : std_logic;
  signal sLane_Sel          : natural range 0 to cTOTAL_ADCS-1;

begin

  sCntIn.en     <= iEN;
  sCntIn.start  <= sExtTrigDel;
  sCntIn.slwClk <= '0';
  sCntIn.slwEn  <= '0';

  oCNT.busy  <= sCntOut.busy or sTrigDelBusy or sExtendBusy;
  oCNT.error <= sCntOut.error;
  oCNT.reset <= sCntOut.reset;
  oCNT.compl <= sCntOut.compl;

  sAdcFast   <= iMSD_CONFIG.cfgPlane(15);
  --sCalTrigEn <= iMSD_CONFIG.cfgPlane(14); --Used only in FOOT
  sHpCfg     <= iMSD_CONFIG.cfgPlane(11 downto 0);

  -- MULTIPLEXER FAST DATA
  oFASTDATA_DATA  <= sFastData_Data_LW when iSWITCH(2) = '1' else sFastData_Data_PE;
  oFASTDATA_WE  <= sFastData_WE_LW when iSWITCH(2) = '1' else sFastData_WE_PE;


  oLED(2)  <= sFastData_WE_LW;
  oLED(3)  <= iSWITCH(2);

  --!@brief Delay the external trigger before the FE start
  TRIG_DELAY : delay_timer
    generic map(
      pWIDTH => 16
    )
    port map(
      iCLK   => iCLK,
      iRST   => iRST,
      iSTART => iTRIG,
      iDELAY => iMSD_CONFIG.trg2Hold,
      oBUSY  => sExtTrigDelBusy,
      oOUT   => sExtTrigDel
      );

  --!@brief delay the Trigger-delay busy
  busy_delay : process (iCLK)
  begin
    if (rising_edge(iCLK)) then
      sTrigDelBusy   <= sExtTrigDelBusy;
      sFeIn.ShiftOut <= '1';
      sFeIn.initRst  <= iTRIG;
    end if;
  end process;

  --!@brief Extend busy from [320 ns, ~20 ms], in multiples of 320 ns
  busy_extend : delay_timer
    generic map(
      pWIDTH => 20
    )
    port map(
      iCLK   => iCLK,
      iRST   => iRST,
      iSTART => sCntOut.compl,
      iDELAY => iMSD_CONFIG.extendBusy & "0000",
      oBUSY  => sExtendBusy,
      oOUT   => open
      );

  --!@brief Low-level multiple ADCs plane interface
  DETECTOR_INTERFACE : multiAdcPlaneInterface
    generic map (
      pACTIVE_EDGE => "F" --"F": falling, "R": rising
      )
    port map (
      iCLK          => iCLK,
      iRST          => iRST,
      -- control interface
      oCNT          => sCntOut,
      iCNT          => sCntIn,
      iFE_CLK_DIV   => iMSD_CONFIG.feClkDiv,
      iFE_CLK_DUTY  => iMSD_CONFIG.feClkDuty,
      iADC_CLK_DIV  => iMSD_CONFIG.adcClkDiv,
      iADC_CLK_DUTY => iMSD_CONFIG.adcClkDuty,
      iADC_DELAY    => iMSD_CONFIG.adcDelay,
      iCFG_FE       => sHpCfg,
      iADC_FAST     => sAdcFast,
      -- FE interface
      oFE0          => oFE0,
      oFE1          => oFE1,
      iFE           => sFeIn,
      -- ADC interface
      oADC0         => oADC0,
      oADC1         => oADC1,
      iMULTI_ADC    => iMULTI_ADC,
      -- FIFO output interface
      oMULTI_FIFO   => sMultiFifoOut,
      iMULTI_FIFO   => sMultiFifoIn
      );

  --!@brief Collects data from the MSD and assembles them in a single packet
  EVENT_BUILDER : priorityEncoder
    generic map (
      pFIFOWIDTH => cREG_WIDTH,         --32
      pFIFODEPTH => cLENCONV_DEPTH
      )
    port map (
      iCLK            => iCLK,
      iRST            => iRST,
      iMULTI_FIFO     => sMultiFifoOut,
      oMULTI_FIFO     => sMultiFifoIn,
      oFASTDATA_DATA  => sFastData_Data_PE,
      oFASTDATA_WE    => sFastData_WE_PE,
      iFASTDATA_AFULL => iFASTDATA_AFULL
      );


    GEN_LW_WORD : for i in 0 to cTOTAL_ADCS-1 generate
      sLW_WORD(i) <= sMultiFifoOut(i).q;
    end generate;
    -- PUTD per LadderWrapper:
    GEN_LW_PUTD : process(iCLK)
      variable vAnyRead : std_logic;
    begin
      if rising_edge(iCLK) then
        if iRST = '1' then
          sLW_PUTD <= '0';
        else
          vAnyRead := '0';

          for i in 0 to cTOTAL_ADCS-1 loop
            vAnyRead := vAnyRead or sMultiFifoIn(i).rd;
          end loop;

          sLW_PUTD <= vAnyRead; --Al ciclo successivo, quando arriva il dato
        end if;
      end if;
    end process GEN_LW_PUTD;

    LW_FASTDATA_PACK : process(iCLK)
    begin
      if rising_edge(iCLK) then
        if iRST = '1' then
          sFastData_Data_LW     <= (others => '0');
          sFastData_WE_LW       <= '0';
          sFastData_Data_LW_LSB <= (others => '0');
          sFastData_LW_HalfFull <= '0';
        else
          sFastData_WE_LW <= '0';

          if sFastData_WE_LW_RAW = '1' then
            if sFastData_LW_HalfFull = '0' then
              sFastData_Data_LW_LSB <= sFastData_Data_LW_RAW;
              sFastData_LW_HalfFull <= '1';
            else
              sFastData_Data_LW <= sFastData_Data_LW_LSB & sFastData_Data_LW_RAW;
              sFastData_WE_LW   <= '1';
              sFastData_LW_HalfFull <= '0';
            end if;
          end if;
        end if;
      end if;
    end process LW_FASTDATA_PACK;

    oLED(1)  <= sLW_Valid_ER;
    LADDER_WRAPPER : LadderWrapper
      generic map(
        pDATA_WIDTH  => cADC_DATA_WIDTH,
        pADC_STRIPS  => cADC_CHANNELS,
        pHEAP_SIZE   => cHEAP_SIZE,
        pADC_NUM     => cTOTAL_ADCS,
        pLTH         => cLTH,
        pHTH         => cHTH,
        pWADDR_WIDTH => ceil_log2(cTOTAL_ADCS * cADC_CHANNELS)
      )
      port map(
        iCLK           => iCLK,
        iRST           => iRST,
        iWORD          => sLW_WORD,
        iPUTD          => sLW_PUTD,
        iTRIG          => iTRIG,
        iFULL          => iFASTDATA_AFULL,
        oTRIG_L        => open,
        oCLUST_ENABLE  => sLW_Clust_EN,
        oVALID_EVT_RAM => sLW_Valid_ER,
        iCAL_ENABLE    => iSWITCH(0),
        iEVT_ENABLE    => iSWITCH(1),
        iTHR_VALID     => '1', -- iSWITCH(3)
        iK1            => cLTH,
        iK2            => cHTH,
        oBUSY          => oLED(0),
        oER_WE         => sFastData_WE_LW_RAW,
        oER_W_ADDR     => sFastData_ADDR_LW_RAW,
        oER_DATA       => sFastData_Data_LW_RAW,
        iPED           => sPedIn_Cal,
        oPED           => sPedOut_Cal,
        iSIGRAW        => sSigRawIn_Cal,
        oSIGRAW        => sSigRawOut_Cal,
        iSIG           => sSigIn_Cal,
        oSIG           => sSigOut_Cal,
        iFLG           => sFlgIn_Cal,
        oFLG           => sFlgOut_Cal,
        oLTH           => sLthOut_Cal,
        oHTH           => sHthOut_Cal,
        oRHT           => sRhtOut_Cal
      );

      EVENT_RAM : parametric_ram_tp
        generic map(
          pWIDTH       => cADC_DATA_WIDTH,
          pDEPTH       => cTOTAL_ADCS * cADC_CHANNELS,
          pUSEDW_WIDTH => ceil_log2(cTOTAL_ADCS * cADC_CHANNELS),
          pFORCE_MLAB  => 0
        )
        port map(
          iCLK     => iCLK,
          iData    => sFastData_Data_LW_RAW,
          iRd_Addr => sClust_Read_Addr,
          iWr_Addr => sFastData_ADDR_LW_RAW,
          iWr_En   => sFastData_WE_LW_RAW,
          oData    => sClust_Read_Data
        );
      
      -- CALIB RAM MUX FOR CLUSTERING
      sSigIn_Cal.RADDR  <= sClust_Read_Addr(ceil_log2(cADC_CHANNELS)-1 downto 0) when sClust_Read_En = '1' else (others => '0');
      sFlgIn_Cal.RADDR  <= sClust_Read_Addr(ceil_log2(cADC_CHANNELS)-1 downto 0) when sClust_Read_En = '1' else (others => '0');

      -- LANE SELECT FOR CLUSTERING
      LANE_SEL : process (iCLK, iRST) is
      begin
        if iRST = '1' then
          sLane_Sel  <= 0;
        elsif rising_edge(iCLK) then
          sLane_Sel  <= to_integer(unsigned(sClust_Read_Addr((ceil_log2(cTOTAL_ADCS * cADC_CHANNELS))-1 downto ceil_log2(cADC_CHANNELS))));
        end if;
      end process LANE_SEL;
      


      -- WIP.
      -- Collego con lo iSWITCH(3). 
      -- Quando la EventRam viene segnalata valida ce viene avviato il clustering vuol dire che l'evento intero è già stato inserito nelle FIFO.
      -- Se iSWITCH(3) è ad uno, viene inviato nelle fifo un altro evento paddato della stessa dimensione di un evento normale, ma con al suo interno
      -- un evento compresso. Scrive nelle FIFO di oFAST_DATA i dati ricevuti in output dal clustering, uniformandoli in pacchetti da 32 bit invece che da 16
      -- Poi quando MSB di oWR_DATA è 1 vuol dire che è terminato l'evento compresso e per le restanti parole utili a chiudere un evento completo è tutto PAD a 0.
      -- Se per qualche motivo il clustering da in uscita più parole di quelle di un evento, allora tronca. Il tutto deve essere al max due eventi
      -- In questo modo, con iSWITCH(3) su si attiva una modalità mixed raw-compressa dove, per ogni evento reale ho una lunghezza di due eventi nei dati.

      -- Mettendo iSWITCH(3), in TdaqModule deve essere modificata al doppio la lunghezza del pacchetto attesa.
      CLUST : ClusterModule
        generic map(
          pADC_NUM     => cTOTAL_ADCS,
          pADC_STRIPS  => cADC_CHANNELS,
          pDATA_WIDTH  => cADC_DATA_WIDTH,
          pUSEDW_WIDTH => ceil_log2(cTOTAL_ADCS * cADC_CHANNELS)
        )
        port map(
          iCLK     => iCLK,
          iRST     => iRST,
          iTRIG    => iTRIG,
          iRD_DATA => sClust_Read_Data,
          oRD_ADDR => sClust_Read_Addr,
          oRD_EN   => sClust_Read_En,
          iREADY   => sLW_Clust_EN,
          iHT      => sHthOut_Cal.DATA(sLane_Sel),
          iLT      => sLthOut_Cal.DATA(sLane_Sel),
          iFLG     => sFlgOut_Cal.DATA(sLane_Sel)(3 downto 0),
          oWR_DATA => open,
          oWR_EN   => open,
          iFULL    => iFASTDATA_AFULL,
          oBUSY    => open,
          oLOST    => open
        );
        

end architecture std;
