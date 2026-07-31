--!@file TdaqModule.vhd
--!brief Wrapper for all of the generic trigger and data acquisition modules
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.basic_package.all;
use work.paperoPackage.all;

--!@copydoc TdaqModule.vhd
entity TdaqModule is
  generic(
    pFDI_WIDTH : natural := 32;
    pFDI_DEPTH : natural := 4096;
    pGW_VER    : std_logic_vector(31 downto 0)
    );
  port (
    iCLK                : in  std_logic;  --!Main clock on the FPGA side
    --Register Array
    iRST                : in  std_logic;  --!Main reset
    iRST_COUNT          : in  std_logic;  --!Counters reset
    iRST_REG            : in  std_logic;  --!Reset of the Register array
    oREG_ARRAY          : out tRegArray;  --!Complete Registers array
    iINT_TS             : in  std_logic_vector(63 downto 0);  --!Internal timestamp
    iEXT_TS             : in  std_logic_vector(63 downto 0);  --!External timestamp
    iHV_MON             : in std_logic_vector(31 downto 0);   --!HV current monitor (for both HEF)
    --Trigger and Busy logic
    iEXT_TRIG           : in std_logic;
    iTRIG_ENABLE        : in  std_logic;
    iCALIBRATION_ACTIVE : in  std_logic;
    iCALIB_VALID        : in  std_logic;
    iRUN_IDLE           : in  std_logic;
    oTRIG               : out std_logic;
    oBUSY               : out std_logic;
    oDATA_IDLE          : out std_logic;
    iTRG_BUSIES_AND     : in  std_logic_vector(7 downto 0);
    iTRG_BUSIES_OR      : in  std_logic_vector(7 downto 0);
    --FastDATA-Detector interface
    iFASTDATA_DATA      : in  std_logic_vector(cREG_WIDTH-1 downto 0);
    iFASTDATA_WE        : in  std_logic;
    oFASTDATA_AFULL     : out std_logic;
    iPACKET_VALID       : in  std_logic;
    iPAYLOAD_WORDS      : in  std_logic_vector(cREG_WIDTH-1 downto 0);
    iTRIG_TYPE          : in  std_logic_vector(7 downto 0);
    --H2F
    iFIFO_H2F_EMPTY     : in  std_logic;  --!FIFO H2F Wait Request
    iFIFO_H2F_DATA      : in  std_logic_vector(31 downto 0);  --!FIFO H2F q
    oFIFO_H2F_RE        : out std_logic;  --!FIFO H2F Read Request
    --F2H
    iFIFO_F2H_AFULL     : in  std_logic;  --!FIFO F2H Almost full
    oFIFO_F2H_WE        : out std_logic;  --!FIFO F2H Write Request
    oFIFO_F2H_DATA      : out std_logic_vector(31 downto 0);  --!FIFO F2H data
    --F2H FAST
    iFIFO_F2HFAST_AFULL : in  std_logic;  --!FIFO F2H FAST Almost full
    oFIFO_F2HFAST_WE    : out std_logic;  --!FIFO F2H Write Request
    oFIFO_F2HFAST_DATA  : out std_logic_vector(31 downto 0)   --!FIFO F2H data
    );
end entity TdaqModule;

--!@copydoc TdaqModule.vhd
architecture std of TdaqModule is
  -- HPS interface
  signal sHkRdrCnt        : tControlIn;
  signal sHkRdrIntstart   : std_logic;
  signal sF2hFastCnt      : tControlIn;
  signal sF2hFastBusy     : std_logic;
  signal sF2hFastWarning  : std_logic;
  signal sCrWarning       : std_logic_vector(2 downto 0);
  signal sMetaDataIn      : tF2hMetadata;
  signal sMetaDataOut     : tF2hMetadata;
  signal sMetaDataRd      : std_logic;
  signal sMetaDataWr      : std_logic;
  signal sMetaDataWrRe    : std_logic;
  signal sMetaDataErr     : std_logic;
  signal sMetaDataEmpty   : std_logic;

  -- Register Array
  signal sRegArray    : tRegArray;
  signal sRegConfigRx : tRegIntf;
  signal sFpgaRegIntf : tFpgaRegIntf;
  signal sRegWarning  : std_logic_vector(31 downto 0);
  signal sRegBusy     : std_logic_vector(31 downto 0);

  -- Fast-Data Input FIFO
  signal sFdiFifoIn    : tFifo32In;
  signal sFdiFifoOut   : tFifo32Out;
  signal sFdiFifoUsedW : std_logic_vector(ceil_log2(pFDI_DEPTH)-1 downto 0);

  -- Trigger and Busy logic
  signal sTrigEn            : std_logic;
  signal sTrigId            : std_logic_vector(15 downto 0);
  signal sTrigCount         : std_logic_vector(31 downto 0);
  signal sExtTrigCount      : std_logic_vector(31 downto 0);
  signal sIntTrigCount      : std_logic_vector(31 downto 0);
  signal sTrigWhenBusyCount : std_logic_vector(7 downto 0);
  signal sTrigCfg           : std_logic_vector(31 downto 0);
  signal sBusy              : std_logic;
  signal sTrig              : std_logic;
  signal sTrigDelayed       : std_logic;

  -- Trigger and detector information
  signal sSsId        : std_logic_vector(7 downto 0);
  signal sTrigType    : std_logic_vector(7 downto 0);

  -- Test unit
  signal sTestUnitEn    : std_logic;
  signal sTestUnitBusy  : std_logic;
  signal sTestUnitCfg   : std_logic_vector(1 downto 0);
  signal sTestUnitData  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sTestUnitWr    : std_logic;
  signal sTestUnitAfull : std_logic;
  signal sPacketLength  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sPacketTrigType : std_logic_vector(7 downto 0);

  -- Metadata del trigger più recente conservato fino al payload
  signal sPendingTrigNum : std_logic_vector(31 downto 0);
  signal sPendingDetId   : std_logic_vector(15 downto 0);
  signal sPendingTrigId  : std_logic_vector(15 downto 0);
  signal sPendingIntTime : std_logic_vector(63 downto 0);
  signal sPendingExtTime : std_logic_vector(63 downto 0);
  signal sPendingBiasSet : std_logic_vector(31 downto 0);
  signal sPendingBiasCur : std_logic_vector(31 downto 0);
  signal sPendingValid   : std_logic;


begin
  -- Register Array assignments
  sTrigEn                 <= iTRIG_ENABLE;
  --
  sF2hFastCnt.en          <= sRegArray(rUNITS_EN)(0);
  sF2hFastCnt.start       <= sRegArray(rUNITS_EN)(0);
  sTestUnitEn             <= sRegArray(rUNITS_EN)(1);
  sHkRdrIntstart          <= sRegArray(rUNITS_EN)(4);
  sHkRdrCnt.start         <= sRegArray(rUNITS_EN)(5);
  sHkRdrCnt.en            <= sRegArray(rUNITS_EN)(6);
  sTestUnitCfg            <= sRegArray(rUNITS_EN)(9 downto 8);
  --
  -- Carico in trigCfg la configurazione del trigger
  -- bit1: 1 | triggerFisico || 0 | triggerCalib
  -- bit0: 0 | esterno || 1 | interno
  sTrigCfg <= sRegArray(rTRIGBUSY_LOGIC)(31 downto 2) & (not iCALIBRATION_ACTIVE) & sRegArray(rTRIGBUSY_LOGIC)(0);

  -- Legacy e Test Unit mantengono la lunghezza configurata. Per i pacchetti di LW si usa il numero di parole realmente scritte nella FIFO più cFASTDATA_OVERHEAD.
  sPacketLength <= sRegArray(rPKT_LEN) when sTestUnitEn = '1' or iTRIG_TYPE = cTRIG_TYPE_LEGACY else std_logic_vector(unsigned(iPAYLOAD_WORDS) + to_unsigned(cFASTDATA_OVERHEAD, cREG_WIDTH));
  sPacketTrigType <= cTRIG_TYPE_LEGACY when sTestUnitEn = '1' else iTRIG_TYPE;

  -- Payload normali associati al trigger in pending
  -- Dump associato ai contatori correnti
  sMetaDataIn.detId   <= sPendingDetId when sPendingValid = '1' else sRegArray(rDET_ID)(15 downto 0);
  sMetaDataIn.pktLen  <= sPacketLength;
  sMetaDataIn.trigNum <= sPendingTrigNum when sPendingValid = '1' else sTrigCount;
  sMetaDataIn.trigId  <= sPendingTrigId when sPendingValid = '1' else sTrigId;

  sSsId <= (others=>'0');
  sTrigType <= sPacketTrigType;
  sMetaDataIn.intTime <= sPendingIntTime(63 downto 8) & sTrigType when sPendingValid = '1' else iINT_TS(31 downto 0) & '1' & "0000000" & sSsId & x"00" & sTrigType;
  sMetaDataIn.extTime <= sPendingExtTime when sPendingValid = '1' else iEXT_TS;
  sMetaDataIn.biasSet <= sPendingBiasSet when sPendingValid = '1' else sRegArray(rHV_PARAM);
  sMetaDataIn.biasCur <= sPendingBiasCur when sPendingValid = '1' else iHV_MON;

  -- Il trigger viene conservato senza accodare subito un descrittore
  METADATA_TRIGGER_LATCH : process(iCLK)
  begin
    if rising_edge(iCLK) then
      if iRST = '1' or sTrigEn = '0' then
        sPendingTrigNum <= (others => '0');
        sPendingDetId   <= (others => '0');
        sPendingTrigId  <= (others => '0');
        sPendingIntTime <= (others => '0');
        sPendingExtTime <= (others => '0');
        sPendingBiasSet <= (others => '0');
        sPendingBiasCur <= (others => '0');
        sPendingValid   <= '0';
      elsif sTrig = '1' then
        sPendingTrigNum <= sTrigCount;
        sPendingDetId   <= sRegArray(rDET_ID)(15 downto 0);
        sPendingTrigId  <= sTrigId;
        -- Gli otto bit meno significativi vengono completati con il tipo
        -- effettivo soltanto quando è nota anche la lunghezza del payload e quando poi vengono effettivamente scritti nella fifo metadata
        sPendingIntTime <= iINT_TS(31 downto 0) & '1' & "0000000" &
                           sSsId & x"00" & x"00";
        sPendingExtTime <= iEXT_TS;
        sPendingBiasSet <= sRegArray(rHV_PARAM);
        sPendingBiasCur <= iHV_MON;
        sPendingValid   <= '1';
      end if;
    end if;
  end process METADATA_TRIGGER_LATCH;

  -- Priority Encoder e TEST vogliono metadata sul trigger stesso. E' necessario un clock di ritardo per scrivere nella FIFO, sennè c'è desync.
  METADATA_TRIGGER_DELAY : process(iCLK)
  begin
    if rising_edge(iCLK) then
      if iRST = '1' or sTrigEn = '0' then
        sTrigDelayed <= '0';
      else
        sTrigDelayed <= sTrig;
      end if;
    end if;
  end process METADATA_TRIGGER_DELAY;


  --Ports assignments
  oREG_ARRAY <= sRegArray;
  oBUSY      <= sBusy;
  oTRIG      <= sTrig;

  oDATA_IDLE <= '1' when sFdiFifoOut.empty = '1' and    -- Fifo vuota
                           sMetaDataEmpty = '1' and     -- Fifo metadati vuota
                           sF2hFastBusy = '0' and       -- FastData non è busy
                           sMetaDataWr = '0' and        -- Non sto scrivendo metadati
                           sMetaDataWrRe = '0' and      -- Non c'è fronte scrittura metadati pending
                           iPACKET_VALID = '0' and      -- Non c'è un pacchetto valido da DetectorInterface
                           sFdiFifoIn.wr = '0' else     -- Non è in corso scrittura in fastData
                '0';

  --!@brief FPGA-HPS communication interfaces
  --!@todo connect sF2hFastBusy to the trigBusyLogic
  HPS_interfaces : HPS_intf
    generic map(
      pGW_VER => pGW_VER
      )
    port map(
      iCLK                => iCLK,
      iRST                => iRST,
      iRST_REG            => iRST_REG,
      --
      oCR_WARNING         => sCrWarning,
      --
      iHK_RDR_CNT         => sHkRdrCnt,
      iHK_RDR_INT_START   => sHkRdrIntstart,
      --
      iF2HFAST_CNT        => sF2hFastCnt,
      oF2HFAST_MD_RD      => sMetaDataRd,
      iF2HFAST_MD_EMPTY   => sMetaDataEmpty,
      iF2HFAST_METADATA   => sMetaDataOut,
      oF2HFAST_BUSY       => sF2hFastBusy,
      oF2HFAST_WARNING    => sF2hFastWarning,
      --
      iREG_ARRAY          => sRegArray,
      oREG_CONFIG_RX      => sRegConfigRx,
      --
      iFDI_FIFO           => sFdiFifoOut,
      oFDI_FIFO_RD        => sFdiFifoIn.rd,
      --
      iFIFO_H2F_EMPTY     => iFIFO_H2F_EMPTY,
      iFIFO_H2F_DATA      => iFIFO_H2F_DATA,
      oFIFO_H2F_RE        => oFIFO_H2F_RE,
      --
      iFIFO_F2H_AFULL     => iFIFO_F2H_AFULL,
      oFIFO_F2H_WE        => oFIFO_F2H_WE,
      oFIFO_F2H_DATA      => oFIFO_F2H_DATA,
      --
      iFIFO_F2HFAST_AFULL => iFIFO_F2HFAST_AFULL,
      oFIFO_F2HFAST_WE    => oFIFO_F2HFAST_WE,
      oFIFO_F2HFAST_DATA  => oFIFO_F2HFAST_DATA
      );

  --!@brief Bank of registers, always enabled
  Config_Registers : registerArray
    port map(
      iCLK       => iCLK,
      iRST       => iRST_REG,
      iCNT       => ('1', '1'),
      oCNT       => open,
      oREG_ARRAY => sRegArray,
      iHPS_REG   => sRegConfigRx,
      iFPGA_REG  => sFpgaRegIntf
      );

  --!@brief PRBS-32 generator
  PRBS_generator : Test_Unit
    port map(
      iCLK            => iCLK,
      iRST            => iRST,
      iEN             => sTestUnitEn and not sTestUnitAfull,
      iSETTING_CONFIG => sTestUnitCfg,
      iSETTING_LENGTH => sRegArray(rPKT_LEN),
      iTRIG           => sTrig,
      oDATA           => sTestUnitData,
      oDATA_VALID     => sTestUnitWr,
      oTEST_BUSY      => sTestUnitBusy
      );

  sFdiFifoIn.data <= iFASTDATA_DATA when sTestUnitEn = '0' else
                     sTestUnitData;
  sFdiFifoIn.wr <= iFASTDATA_WE when sTestUnitEn = '0' else
                   sTestUnitWr;
  sTestUnitAfull  <= sFdiFifoOut.aFull;
  oFASTDATA_AFULL <= sFdiFifoOut.aFull;
  --!@brief FIFO in input of the fast data tx
  fast_data_input_FDI_fifo : parametric_fifo_synch
    generic map(
      pWIDTH       => pFDI_WIDTH,
      pDEPTH       => pFDI_DEPTH,
      pUSEDW_WIDTH => ceil_log2(pFDI_DEPTH),
      pAEMPTY_VAL  => 2,
      pAFULL_VAL   => pFDI_DEPTH-cMAX_WORDS_PER_EVT*2-3,
      pSHOW_AHEAD  => "OFF"
      )
    port map(
      iCLK    => iCLK,
      iRST    => iRST,
      oUSEDW  => sFdiFifoUsedW,
      -- Write interface
      oAFULL  => sFdiFifoOut.aFull,
      oFULL   => sFdiFifoOut.full,
      iWR_REQ => sFdiFifoIn.wr,
      iDATA   => sFdiFifoIn.data,
      -- Read interface
      oAEMPTY => sFdiFifoOut.aEmpty,
      oEMPTY  => sFdiFifoOut.Empty,
      iRD_REQ => sFdiFifoIn.rd,
      oQ      => sFdiFifoOut.q
      );


  --!@brief Trigger and busy logic
  Trig_Busy : trigBusyLogic
    port map (
      iCLK            => iCLK,
      iRST            => iRST or not sTrigEn,
      iRST_COUNTERS   => iRST_COUNT,
      iCFG            => sTrigCfg,
      iEXT_TRIG       => iEXT_TRIG,
      iBUSIES_AND     => iTRG_BUSIES_AND,
      iBUSIES_OR      => iTRG_BUSIES_OR,
      oTRIG           => sTrig,
      oTRIG_ID        => sTrigId,
      oTRIG_COUNT     => sTrigCount,
      oEXT_TRIG_COUNT => sExtTrigCount,
      oINT_TRIG_COUNT => sIntTrigCount,
      oTRIG_WHEN_BUSY => sTrigWhenBusyCount,
      oBUSY           => sBusy
      );

  sMetaDataWr <= sTrigDelayed when sTestUnitEn = '1' or iTRIG_TYPE = cTRIG_TYPE_LEGACY else iPACKET_VALID;

  MD_WR_ED : edge_detector
    port map(
      iCLK    => iCLK,
      iRST    => '0',
      iD      => sMetaDataWr,
      oEDGE_R => sMetaDataWrRe
    );
  metaDataFifo_i : metaDataFifo
    generic map(
      pFIFOs => 9,
      pWIDTH => 32
    )
    port map (
      iCLK      => iCLK,
      iRST      => iRST or not sTrigEn,
      oERR      => sMetaDataErr,
      iRD       => sMetaDataRd,
      iWR       => sMetaDataWrRe,
      oEMPTY    => sMetaDataEmpty,
      iMETADATA => sMetaDataIn,
      oMETADATA => sMetaDataOut
    );


  -- FPGA-registers mapping
  sFpgaRegIntf.regs(rGW_VER)     <= pGW_VER;
  sFpgaRegIntf.we(rGW_VER)       <= '1';
  sFpgaRegIntf.regs(rINT_TS_MSB) <= iINT_TS(63 downto 32);
  sFpgaRegIntf.we(rINT_TS_MSB)   <= '1';
  sFpgaRegIntf.regs(rINT_TS_LSB) <= iINT_TS(31 downto 0);
  sFpgaRegIntf.we(rINT_TS_LSB)   <= '1';
  sFpgaRegIntf.regs(rEXT_TS_MSB) <= iEXT_TS(63 downto 32);
  sFpgaRegIntf.we(rEXT_TS_MSB)   <= '1';
  sFpgaRegIntf.regs(rEXT_TS_LSB) <= iEXT_TS(31 downto 0);
  sFpgaRegIntf.we(rEXT_TS_LSB)   <= '1';
  sFpgaRegIntf.regs(rWARNING)    <= sRegWarning;
  sFpgaRegIntf.we(rWARNING)      <= '1';
  sFpgaRegIntf.regs(rBUSY)       <= sRegBusy;
  sFpgaRegIntf.we(rBUSY)         <= '1';
  sFpgaRegIntf.regs(rEXT_TRG_COUNT)  <= sExtTrigCount;
  sFpgaRegIntf.we(rEXT_TRG_COUNT)    <= '1';
  sFpgaRegIntf.regs(rINT_TRG_COUNT)  <= sIntTrigCount;
  sFpgaRegIntf.we(rINT_TRG_COUNT)    <= '1';
  sFpgaRegIntf.regs(rFDI_FIFO_NUMWORD)
    (sFdiFifoUsedW'left downto 0) <= sFdiFifoUsedW;
  sFpgaRegIntf.regs(rFDI_FIFO_NUMWORD)
    (cREG_WIDTH-1 downto sFdiFifoUsedW'left+1) <= (others => '0');
  sFpgaRegIntf.we(rFDI_FIFO_NUMWORD) <= '1';
  sFpgaRegIntf.regs(rHV_CURR_MON)    <= iHV_MON;
  sFpgaRegIntf.we(rHV_CURR_MON)      <= '1';
  sFpgaRegIntf.regs(rCALIB_STATUS)   <= (0 => iCALIB_VALID, 1 => iRUN_IDLE, others => '0');
  sFpgaRegIntf.we(rCALIB_STATUS)     <= '1';
  sFpgaRegIntf.regs(12)              <= (others => '0');
  sFpgaRegIntf.we(12)                <= '0';
  sFpgaRegIntf.regs(13)              <= (others => '0');
  sFpgaRegIntf.we(13)                <= '0';
  sFpgaRegIntf.regs(14)              <= (others => '0');
  sFpgaRegIntf.we(14)                <= '0';
  sFpgaRegIntf.regs(rPIUMONE)        <= x"c1a0c1a0";
  sFpgaRegIntf.we(rPIUMONE)          <= '1';

  sRegWarning <= x"00000" & "00" & sMetaDataErr & sF2hFastWarning & x"0" & "0" & sCrWarning;
  sRegBusy    <= sBusy & "00" & sTestUnitBusy & iTRG_BUSIES_AND & iTRG_BUSIES_OR & sF2hFastBusy
              & iFIFO_F2H_AFULL & iFIFO_F2HFAST_AFULL
              & sFdiFifoOut.aFull & sTrigWhenBusyCount;

end architecture std;
