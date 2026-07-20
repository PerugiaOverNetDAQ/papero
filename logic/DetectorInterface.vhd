--!@file DetectorInterface.vhd
--!@brief Instantiate the Data_Builder.vhd and the multiAdcPlaneInterface.vhd
--!@details Top to interconnect all of the u-strip-related modules
--!@author Mattia Barbanera (mattia.barbanera@infn.it)
--!@author Keida Kanxheri (keida.kanxheri@pg.infn.it)
--!@author Luca Russo, luca.russo@cern.ch, luca.russo912@gmail.com

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
    oPACKET_VALID   : out std_logic;    --!Payload descriptor valid
    oPAYLOAD_WORDS  : out std_logic_vector(cREG_WIDTH-1 downto 0);
    oTRIG_TYPE      : out std_logic_vector(7 downto 0);
    iTHR_VALID      : in  std_logic;
    iLTH            : in  std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
    iHTH            : in  std_logic_vector(cADC_DATA_WIDTH-1 downto 0);

    iSWITCH         : in std_logic_vector(3 downto 0);
    oLED            : out std_logic_vector(3 downto 0)
    );
end DetectorInterface;

--!@copydoc DetectorInterface.vhd
architecture std of DetectorInterface is
  -- Numero di parole 32 bit in un payload RAW
  constant cLW_EVENT_WORDS : positive :=
    (cTOTAL_ADCS * cADC_CHANNELS * cADC_DATA_WIDTH) / cREG_WIDTH;
  constant cMODE_LEGACY     : std_logic_vector(1 downto 0) := "00"; --SW[3:2]
  constant cMODE_RAW        : std_logic_vector(1 downto 0) := "01";
  constant cMODE_COMPRESSED : std_logic_vector(1 downto 0) := "10";
  constant cMODE_MIXED      : std_logic_vector(1 downto 0) := "11";

  type tLW_Output_State is (RAW_OUTPUT, CLUSTER_OUTPUT, DISCARD_OUTPUT);

  function fCalibTrigType(
    iCalibType : std_logic_vector(1 downto 0)
  ) return std_logic_vector is
  begin
    case iCalibType is
      when "00"   => return cTRIG_TYPE_PEDESTAL;
      when "01"   => return cTRIG_TYPE_SIGMA_RAW;
      when "10"   => return cTRIG_TYPE_SIGMA;
      when others => return cTRIG_TYPE_FLAG;
    end case;
  end function fCalibTrigType;

  function fClusterWordLimit(
    iMode : std_logic_vector(1 downto 0)
  ) return positive is
  begin
    if iMode = cMODE_MIXED then
      -- Una RAW e al massimo una RAW-equivalente compressa (quindi taglio prima del doppio) tot 5164byte header compreso
      return cLW_EVENT_WORDS;
    else
      -- Il solo compresso può occupare al massimo due RAW-equivalenti tot max sempre 5164 byte
      return 2 * cLW_EVENT_WORDS;
    end if;
  end function fClusterWordLimit;

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
  signal sLW_Output_State      : tLW_Output_State;
  signal sUse_LadderWrapper    : std_logic;
  signal sNormal_Event_Armed   : std_logic;
  signal sEvent_Mode           : std_logic_vector(1 downto 0);
  signal sPacket_Busy          : std_logic;
  -- Descrittore del payload reale
  signal sPacket_Valid_LW      : std_logic;
  signal sPayload_Words_LW     : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sTrig_Type_LW         : std_logic_vector(7 downto 0);
  signal sCalib_Packet_Type    : std_logic_vector(7 downto 0);
  signal sRaw_Packet_Word_Count : natural range 0 to cLW_EVENT_WORDS-1;

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
  signal sLW_Event_Accepted : std_logic;
  signal sLW_Calib_Type : std_logic_vector(1 downto 0);

  -- CLUSTERING
  signal sClust_Read_Addr   : std_logic_vector((ceil_log2(cTOTAL_ADCS * cADC_CHANNELS))-1 downto 0);
  signal sClust_Read_Data   : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sClust_Read_En     : std_logic;
  signal sLane_Sel          : natural range 0 to cTOTAL_ADCS-1;
  signal sClust_Write_Data  : std_logic_vector(cADC_DATA_WIDTH downto 0);
  signal sClust_Write_En    : std_logic;
  signal sClust_Start       : std_logic;
  signal sClust_Full        : std_logic;
  signal sClust_Busy        : std_logic;
  signal sClust_Data_MSB    : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sClust_HalfFull    : std_logic;
  signal sCluster_Word_Count : natural range 0 to (2*cLW_EVENT_WORDS)-1;
  -- Soglie LANE selezionata per il clustering
  signal sClust_HT          : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sClust_LT          : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sClust_FLG         : std_logic_vector(3 downto 0);

begin

  sCntIn.en     <= iEN;
  sCntIn.start  <= sExtTrigDel;
  sCntIn.slwClk <= '0';
  sCntIn.slwEn  <= '0';

  oCNT.busy  <= sCntOut.busy or sTrigDelBusy or sExtendBusy or
                sClust_Busy or sPacket_Busy;
  oCNT.error <= sCntOut.error;
  oCNT.reset <= sCntOut.reset;
  oCNT.compl <= sCntOut.compl;

  sAdcFast   <= iMSD_CONFIG.cfgPlane(15);
  --sCalTrigEn <= iMSD_CONFIG.cfgPlane(14); --Used only in FOOT
  sHpCfg     <= iMSD_CONFIG.cfgPlane(11 downto 0);

  -- SW(3 downto 2): 00 Legacy, 01 Raw, 10 Compressed, 11 Mixed. Invertito rispetto a com'è la box in LAB
  sUse_LadderWrapper <= '0' when iSWITCH(3 downto 2) = cMODE_LEGACY else '1';
  sPacket_Busy <= '1' when sLW_Output_State /= RAW_OUTPUT else '0';

  -- In Legacy i metadati restano legati al trigger e usa la lunghezza configurata in TdaqModule. Il LadderWrapper pubblica metadata solo
  -- dopo EOP (o dopo il troncamento se c'è), quando la lunghezza reale è nota.
  oPACKET_VALID  <= sPacket_Valid_LW when sUse_LadderWrapper = '1' else iTRIG;
  oPAYLOAD_WORDS <= sPayload_Words_LW when sUse_LadderWrapper = '1' else (others => '0');
  oTRIG_TYPE     <= sTrig_Type_LW when sUse_LadderWrapper = '1' else
                    cTRIG_TYPE_LEGACY;
  -- Durante il troncamento i cluster rimanenti sono eliminati in locale, non si risponde al full
  sClust_Full <= iFASTDATA_AFULL when sLW_Output_State = CLUSTER_OUTPUT else '0';
  sClust_Start <= sLW_Clust_EN and sNormal_Event_Armed when sEvent_Mode = cMODE_COMPRESSED or sEvent_Mode = cMODE_MIXED else '0';

  -- MULTIPLEXER FAST DATA
  oFASTDATA_DATA <= sFastData_Data_LW when sUse_LadderWrapper = '1' else
                    sFastData_Data_PE;
  oFASTDATA_WE   <= sFastData_WE_LW when sUse_LadderWrapper = '1' else
                    sFastData_WE_PE;


  oLED(2)  <= sFastData_WE_LW;
  oLED(3)  <= sUse_LadderWrapper;

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
      variable vClusterWordLimit : positive;
      variable vPayloadWords     : natural;
    begin
      if rising_edge(iCLK) then
        if iRST = '1' then
          sFastData_Data_LW      <= (others => '0');
          sFastData_WE_LW        <= '0';
          sFastData_Data_LW_LSB  <= (others => '0');
          sFastData_LW_HalfFull  <= '0';
          sLW_Output_State       <= RAW_OUTPUT;
          sNormal_Event_Armed    <= '0';
          sEvent_Mode            <= cMODE_LEGACY;
          sClust_Data_MSB        <= (others => '0');
          sClust_HalfFull        <= '0';
          sCluster_Word_Count    <= 0;
          sPacket_Valid_LW       <= '0';
          sPayload_Words_LW      <= (others => '0');
          sTrig_Type_LW          <= (others => '0');
          sCalib_Packet_Type     <= cTRIG_TYPE_PEDESTAL;
          sRaw_Packet_Word_Count <= 0;
        else
          sFastData_WE_LW  <= '0';
          sPacket_Valid_LW <= '0';

          -- La mode è salvata sul trigger accettato: i dati RAW arrivano molto più tardi e non devono dipendere da cambi degli switch
          if sLW_Event_Accepted = '1' and sUse_LadderWrapper = '1' then
            sEvent_Mode         <= iSWITCH(3 downto 2);
            sNormal_Event_Armed <= '1';
          end if;

          case sLW_Output_State is
            when RAW_OUTPUT =>
              if sFastData_WE_LW_RAW = '1' then
                if sFastData_LW_HalfFull = '0' then
                  sFastData_Data_LW_LSB <= sFastData_Data_LW_RAW;
                  sFastData_LW_HalfFull <= '1';
                else
                  sFastData_LW_HalfFull <= '0';

                  -- In Compressed la RAW alimenta soltanto Event RAM, non le FIFO. In Raw, Mixed e nelle tabelle di calibrazione viene inoltrata.
                  if not (sNormal_Event_Armed = '1' and sEvent_Mode = cMODE_COMPRESSED) then
                    sFastData_Data_LW <= sFastData_Data_LW_LSB & sFastData_Data_LW_RAW;
                    sFastData_WE_LW <= '1';
                  end if;

                  -- Il tipo di tabella calibrazione viene campionato all'inizio: sCWState puè avanzare mentre l'ultima parola attraversa i registri di LadderWrapper.
                  if sRaw_Packet_Word_Count = 0 and sNormal_Event_Armed = '0' then
                    sCalib_Packet_Type <= fCalibTrigType(sLW_Calib_Type);
                  end if;

                  if sRaw_Packet_Word_Count = cLW_EVENT_WORDS-1 then
                    sRaw_Packet_Word_Count <= 0;

                    if sNormal_Event_Armed = '1' then
                      if sEvent_Mode = cMODE_RAW then
                        sPayload_Words_LW <= std_logic_vector(to_unsigned(cLW_EVENT_WORDS, cREG_WIDTH));
                        sTrig_Type_LW       <= cTRIG_TYPE_RAW;
                        sPacket_Valid_LW    <= '1';
                        sNormal_Event_Armed <= '0';
                      end if;
                    else
                      -- PED, SIGRAW, SIG e FLG hanno tutte dimensione RAW fisse
                      sPayload_Words_LW <= std_logic_vector(to_unsigned(cLW_EVENT_WORDS, cREG_WIDTH));
                      sTrig_Type_LW    <= sCalib_Packet_Type;
                      sPacket_Valid_LW <= '1';
                    end if;
                  else
                    sRaw_Packet_Word_Count <=
                      sRaw_Packet_Word_Count + 1;
                  end if;
                end if;
              end if;

              -- La RAW finale e l'abilitazione possono accadere contemporaneamente nello stesso CLK. Il dato RAW viene quindi gestito
              -- sopra prima di passare allo stream compresso
              if sLW_Clust_EN = '1' and sNormal_Event_Armed = '1' and (sEvent_Mode = cMODE_COMPRESSED or sEvent_Mode = cMODE_MIXED) then
                sLW_Output_State    <= CLUSTER_OUTPUT;
                sClust_HalfFull     <= '0';
                sCluster_Word_Count <= 0;
              end if;

            when CLUSTER_OUTPUT =>
              vClusterWordLimit := fClusterWordLimit(sEvent_Mode);

              if sClust_Write_En = '1' then
                if sClust_HalfFull = '0' then
                  if sClust_Write_Data(cADC_DATA_WIDTH) = '1' then
                    -- EOP dispari (ossia nella prima metà): resta soltanto la mezza parola necessaria
                    -- all'allineamento della FIFO a 32 bit, non è un padding a dimensione massima
                    sFastData_Data_LW <= sClust_Write_Data(cADC_DATA_WIDTH-1 downto 0) & std_logic_vector(to_unsigned(0, cADC_DATA_WIDTH));
                    sFastData_WE_LW <= '1';

                    vPayloadWords := sCluster_Word_Count + 1;
                    if sEvent_Mode = cMODE_MIXED then
                      vPayloadWords := vPayloadWords + cLW_EVENT_WORDS;
                      sTrig_Type_LW <= cTRIG_TYPE_MIXED;
                    else
                      sTrig_Type_LW <= cTRIG_TYPE_COMPRESSED;
                    end if;

                    sPayload_Words_LW <= std_logic_vector(to_unsigned(vPayloadWords, cREG_WIDTH));
                    sPacket_Valid_LW    <= '1';
                    sNormal_Event_Armed <= '0';
                    sLW_Output_State    <= DISCARD_OUTPUT;
                  else
                    sClust_Data_MSB <=
                      sClust_Write_Data(cADC_DATA_WIDTH-1 downto 0);
                    sClust_HalfFull <= '1';
                  end if;
                else
                  sFastData_Data_LW <=
                    sClust_Data_MSB &
                    sClust_Write_Data(cADC_DATA_WIDTH-1 downto 0);
                  sFastData_WE_LW <= '1';
                  sClust_HalfFull <= '0';

                  -- La parola corrente chiude il payload sull'EOP oppure sul limite: 2 RAW complessive sia per Compressed sia per Mixed
                  if sClust_Write_Data(cADC_DATA_WIDTH) = '1' or
                     sCluster_Word_Count = vClusterWordLimit-1 then
                    vPayloadWords := sCluster_Word_Count + 1;
                    if sEvent_Mode = cMODE_MIXED then
                      vPayloadWords := vPayloadWords + cLW_EVENT_WORDS;
                      sTrig_Type_LW <= cTRIG_TYPE_MIXED;
                    else
                      sTrig_Type_LW <= cTRIG_TYPE_COMPRESSED;
                    end if;

                    sPayload_Words_LW <= std_logic_vector(
                      to_unsigned(vPayloadWords, cREG_WIDTH));
                    sPacket_Valid_LW    <= '1';
                    sNormal_Event_Armed <= '0';
                    sLW_Output_State    <= DISCARD_OUTPUT;
                  else
                    sCluster_Word_Count <= sCluster_Word_Count + 1;
                  end if;
                end if;
              end if;

            when DISCARD_OUTPUT =>
              -- Dopo EOP o troncamento ClusterModule viene lasciato scaricare localmente, senza rispondere ad iFULL. Nessun'altra parola entra nella FIFO fastdata.
              if sClust_Busy = '0' then
                sLW_Output_State <= RAW_OUTPUT;
                sClust_HalfFull  <= '0';
              end if;

            when others =>
              sLW_Output_State    <= RAW_OUTPUT;
              sNormal_Event_Armed <= '0';
          end case;
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
        oEVENT_ACCEPTED => sLW_Event_Accepted,
        oCALIB_TYPE    => sLW_Calib_Type,
        iCAL_ENABLE    => iSWITCH(0),
        iEVT_ENABLE    => iSWITCH(1),
        iTHR_VALID     => iTHR_VALID,
        iK1            => iLTH,
        iK2            => iHTH,
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
      
      -- Interfaccia di sola lettura della RAM di calibrazione usata dal clustering
      -- I campi non utilizzati restano a zero
      sPedIn_Cal.DATA     <= (others => (others => '0'));
      sPedIn_Cal.WADDR    <= (others => '0');
      sPedIn_Cal.RADDR    <= (others => '0');
      sPedIn_Cal.WE       <= '0';

      sSigRawIn_Cal.DATA  <= (others => (others => '0'));
      sSigRawIn_Cal.WADDR <= (others => '0');
      sSigRawIn_Cal.RADDR <= (others => '0');
      sSigRawIn_Cal.WE    <= '0';

      sSigIn_Cal.DATA     <= (others => (others => '0'));
      sSigIn_Cal.WADDR    <= (others => '0');
      sSigIn_Cal.WE       <= '0';
      sSigIn_Cal.RADDR    <= sClust_Read_Addr(ceil_log2(cADC_CHANNELS)-1 downto 0) when sClust_Read_En = '1' else (others => '0');

      sFlgIn_Cal.DATA     <= (others => (others => '0'));
      sFlgIn_Cal.WADDR    <= (others => '0');
      sFlgIn_Cal.WE       <= '0';
      sFlgIn_Cal.RADDR    <= sClust_Read_Addr(ceil_log2(cADC_CHANNELS)-1 downto 0) when sClust_Read_En = '1' else (others => '0');

      -- LANE SELECT FOR CLUSTERING
      LANE_SEL : process (iCLK, iRST) is
      begin
        if iRST = '1' then
          sLane_Sel  <= 0;
        elsif rising_edge(iCLK) then
          if sClust_Read_En = '1' then
            sLane_Sel <= to_integer(unsigned(
              sClust_Read_Addr(
                ceil_log2(cTOTAL_ADCS * cADC_CHANNELS)-1 downto
                ceil_log2(cADC_CHANNELS)
              )
            ));
          end if;
        end if;
      end process LANE_SEL;

      -- Il multiplexer resta esterno alla associazione delle porte
      sClust_HT  <= sHthOut_Cal.DATA(sLane_Sel);
      sClust_LT  <= sLthOut_Cal.DATA(sLane_Sel);
      sClust_FLG <= sFlgOut_Cal.DATA(sLane_Sel)(3 downto 0);

      -- ClusterModule parte solo dopo il completamento di un evento normale
      -- I trigger di calibrazione non possono avviare il clustering
      -- Lo stream termina all'EOP senza padding e viene troncato al limite.
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
          iTRIG    => sClust_Start,
          iRD_DATA => sClust_Read_Data,
          oRD_ADDR => sClust_Read_Addr,
          oRD_EN   => sClust_Read_En,
          iREADY   => sLW_Clust_EN,
          iHT      => sClust_HT,
          iLT      => sClust_LT,
          iFLG     => sClust_FLG,
          oWR_DATA => sClust_Write_Data,
          oWR_EN   => sClust_Write_En,
          iFULL    => sClust_Full,
          oBUSY    => sClust_Busy,
          oLOST    => open
        );
        

end architecture std;
