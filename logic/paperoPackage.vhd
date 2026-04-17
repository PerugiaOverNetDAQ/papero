--!@file paperoPackage.vhd
--!@brief Constants, components declarations, and functions
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.basic_package.all;
use work.FOOTpackage.all;

--!@copydoc paperoPackage.vhd
package paperoPackage is
  -- Constants -----------------------------------------------------------------
  constant cREG_WIDTH      : natural := 32;  --!Register width
  constant cHPS_REGISTERS  : natural := 16;  --!Number of HPS-RW, FPGA-R registers
  constant cFPGA_REGISTERS : natural := 16;  --!Number of HPS-R, FPGA-RW registers
  constant cREGISTERS      : natural := cHPS_REGISTERS + cFPGA_REGISTERS;  --!Total number of registers

  constant cHPS_REG_ADDR  : natural := ceil_log2(cHPS_REGISTERS);  --!Register address width
  constant cFPGA_REG_ADDR : natural := ceil_log2(cFPGA_REGISTERS);  --!Register address width

  constant cFDI_WIDTH     : natural := 32;  --!Width of FDI FIFO
  constant cFDI_DEPTH     : natural := 4096;  --!Number of words in the FDI FIFO
  constant cLENCONV_DEPTH : natural := 16;  --!Number of words in the length converter FIFO

  --Housekeeping reader
  constant cF2H_HK_SOP    : std_logic_vector(31 downto 0) := x"55AADEAD";  --!Start of Packet for the FPGA-2-HPS FSM
  constant cF2H_HK_HDR    : std_logic_vector(31 downto 0) := x"4EADE500";  --!Fixed Header for the FPGA-2-HPS FSM
  constant cF2H_HK_EOP    : std_logic_vector(31 downto 0) := x"600DF00D";  --!End of Packet for the FPGA-2-HPS FSM
  constant cF2H_HK_PERIOD : natural                       := 50000000;  --!Period for internal counter to read HKs; max: 2^32 (85 s)
  constant cF2H_AFULL     : natural                       := 949;  --!Almost full threshold for the HK FIFO: 1021 - (6 + 32*2) - 2
  constant cFastF2H_AFULL : natural                       := 4085;  --!Almost full threshold for the data FIFO

  --Trigger types
  constant cTRG_PHYS_INT  : std_logic_vector(15 downto 0) := x"0001";  --!Physics trigger (from internal counter)
  constant cTRG_PHYS_EXT  : std_logic_vector(15 downto 0) := x"0002";  --!Physics trigger (from external pin)
  constant cTRG_CALIB_INT : std_logic_vector(15 downto 0) := x"0004";  --!Calibration trigger (internal)
  constant cTRG_CALIB_EXT : std_logic_vector(15 downto 0) := x"0008";  --!Calibration trigger (external)

  -- Types ---------------------------------------------------------------------
  constant rGOTO_STATE     : natural := 0;
  constant rUNITS_EN       : natural := 1;
  constant rTRIGBUSY_LOGIC : natural := 2;
  constant rDET_ID         : natural := 3;
  constant rPKT_LEN        : natural := 4;
  constant rFE_CLK_PARAM   : natural := 5;
  constant rADC_CLK_PARAM  : natural := 6;
  constant rMSD_PARAM      : natural := 7;
  constant rBUSYADC_PARAM  : natural := 8;
  constant rTRGBRD_CFG     : natural := 9;
  constant rTRGBRD_FREQDIV : natural := 10;
  constant rTRGBRD_DUTY    : natural := 11;
  constant rERLANG_THRSH   : natural := 12;
  constant rERLANG_INTBUSY : natural := 13;
  constant rERLANG_DUTY    : natural := 14;
  
  --!Register array HPS-RW, FPGA-R
  type tHpsRegArray is array (0 to cHPS_REGISTERS-1) of
    std_logic_vector(cREG_WIDTH-1 downto 0);
  constant cHPS_REG_NULL : tHpsRegArray := (
    x"00000000", x"00000001", x"02faf080", x"000000FF",
    x"0000028A", cFE_CLK_DUTY & cFE_CLK_DIV, cADC_CLK_DUTY & cADC_CLK_DIV , cCFG_PLANE & cTRG2HOLD,
    cBUSY_LEN & cADC_DELAY, x"00000000", x"00000032", x"00000019",
    x"80000000", x"00000001", x"00000032", x"00000000"
    );                                  --!Null vector for HPS register array

  constant rGW_VER           : natural := 0;
  constant rINT_TS_MSB       : natural := 1;
  constant rINT_TS_LSB       : natural := 2;
  constant rEXT_TS_MSB       : natural := 3;
  constant rEXT_TS_LSB       : natural := 4;
  constant rWARNING          : natural := 5;
  constant rBUSY             : natural := 6;
  constant rEXT_TRG_COUNT    : natural := 7;
  constant rINT_TRG_COUNT    : natural := 8;
  constant rFDI_FIFO_NUMWORD : natural := 9;
  constant rPIUMONE          : natural := 15;
  --!Register array HPS-R, FPGA-RW
  type tFpgaRegArray is array (0 to cFPGA_REGISTERS-1) of
    std_logic_vector(cREG_WIDTH-1 downto 0);
  constant cFPGA_REG_NULL : tFpgaRegArray := (
    x"a0a0a0a0", x"00000000", x"00000000", x"00000000",
    x"00000000", x"00000000", x"00000000", x"00000000",
    x"00000000", x"00000000", x"00000000", x"00000000",
    x"00000000", x"00000000", x"00000000", x"c1a0c1a0"
    );                                  --!Null vector for FPGA register array

  --!Complete Registers array
  type tRegArray is array (0 to cREGISTERS-1) of
    std_logic_vector(cREG_WIDTH-1 downto 0);

  --!Registers interface
  type tRegIntf is record
    reg  : std_logic_vector(cREG_WIDTH-1 downto 0);  --!Content to be written
    addr : std_logic_vector(cHPS_REG_ADDR-1 downto 0);  --!Address to be updated
    we   : std_logic;                   --!Write enable
  end record tRegIntf;

  --!FPGA Registers interface
  type tFpgaRegIntf is record
    regs : tFpgaRegArray;               --!FPGA registers
    we   : std_logic_vector(cFPGA_REGISTERS-1 downto 0);  --!Write enable vector
  end record tFpgaRegIntf;

  --!Control interface for a generic block: input signals
  type tControlIn is record
    en    : std_logic;                  --!Enable
    start : std_logic;                  --!Start
  end record tControlIn;

  --!Control interface for a generic block: output signals
  type tControlOut is record
    busy  : std_logic;                  --!Busy flag
    error : std_logic;                  --!Error flag
    reset : std_logic;                  --!Resetting flag
    compl : std_logic;                  --!completion of task
  end record tControlOut;

  --!CRC32 interface (do not use it as port)
  type tCrc32 is record
    rst  : std_logic;
    en   : std_logic;                      --!Write enable
    data : std_logic_vector(31 downto 0);  --!Input data
    crc  : std_logic_vector(31 downto 0);  --!CRC32 out
  end record tCrc32;

  --!Input signals of a typical FIFO memory of 32 bit
  type tFifo32In is record
    data : std_logic_vector(31 downto 0);  --!Input data port
    rd   : std_logic;                      --!Read request
    wr   : std_logic;                      --!Write request
  end record tFifo32In;

  --!Output signals of a typical FIFO memory of 32 bit
  type tFifo32Out is record
    q      : std_logic_vector(31 downto 0);  --!Output data port
    aEmpty : std_logic;                      --!Almost empty
    empty  : std_logic;                      --!Empty
    aFull  : std_logic;                      --!Almost full
    full   : std_logic;                      --!Full
  end record tFifo32Out;

  --!Input signals of a typical FIFO memory of cFDI_WIDTH bit
  type tFifoFdiIn is record
    data : std_logic_vector(cFDI_WIDTH-1 downto 0);  --!Input data port
    rd   : std_logic;                                --!Read request
    wr   : std_logic;                                --!Write request
  end record tFifoFdiIn;

  --!Output signals of a typical FIFO memory of cFDI_WIDTH bit
  type tFifoFdiOut is record
    q      : std_logic_vector(cFDI_WIDTH-1 downto 0);  --!Output data port
    aEmpty : std_logic;                                --!Almost empty
    empty  : std_logic;                                --!Empty
    aFull  : std_logic;                                --!Almost full
    full   : std_logic;                                --!Full
  end record tFifoFdiOut;

  --!Metadata for the F2H Fast TX
  type tF2hMetadata is record
    pktLen  : std_logic_vector(31 downto 0);  --!Packet Length: Number of 32-bit payload words + 10
    trigNum : std_logic_vector(31 downto 0);  --!Trigger Counter
    detId   : std_logic_vector(15 downto 0);  --!Detector ID
    trigId  : std_logic_vector(15 downto 0);  --!Trigger ID
    intTime : std_logic_vector(63 downto 0);  --!Internal Timestamp
    extTime : std_logic_vector(63 downto 0);  --!External Timestamp
  end record tF2hMetadata;
  
  --!Erlang Random Trigger configuration
  type tErlangConfig is record
    en          : std_logic;                      --!Enable
    erlangTrig  : std_logic;                      --!Erlang/Periodic type trigger
    thrshLevel  : std_logic_vector(31 downto 0);  --!Threshold Level to generate trigger
    intBusy     : std_logic_vector(31 downto 0);  --!Internal Busy between one trigger and another
    pulseWidth  : std_logic_vector(31 downto 0);  --!Pulse trigger duty cycle
    freqDiv     : std_logic_vector(31 downto 0);  --!Comparison frequency and period of the periodic trigger
  end record tErlangConfig;
  

  -- Components ----------------------------------------------------------------
  --!Detects rising and falling edges of the input
  component edge_detector_md is
    generic(
      channels : integer   := 1;
      R_vs_F   : std_logic := '0'
      );
    port(
      iCLK  : in  std_logic;
      iRST  : in  std_logic;
      iD    : in  std_logic_vector(channels - 1 downto 0);
      oEDGE : out std_logic_vector(channels - 1 downto 0)
      );
  end component;

  --!Generates a single clock pulse when a button is pressed
  component Key_Pulse_Gen is
    port(
      KPG_CLK_in   : in  std_logic;
      KPG_DATA_in  : in  std_logic_vector(1 downto 0);
      KPG_DATA_out : out std_logic_vector(1 downto 0)
      );
  end component;

  --!Allunga di un ciclo di clock lo stato "alto" del segnale di "Wait_Request"
  component HighHold is
    generic(
      channels   : integer   := 1;
      BAS_vs_BSS : std_logic := '0'
      );
    port(
      CLK_in      : in  std_logic;
      DATA_in     : in  std_logic_vector(channels - 1 downto 0);
      DELAY_1_out : out std_logic_vector(channels - 1 downto 0);
      DELAY_2_out : out std_logic_vector(channels - 1 downto 0);
      DELAY_3_out : out std_logic_vector(channels - 1 downto 0);
      DELAY_4_out : out std_logic_vector(channels - 1 downto 0)
      );
  end component;

  --!Temporizza l'invio di impulsi sul read_enable della FIFO
  component WR_Timer is
    port(
      WRT_CLK_in              : in  std_logic;
      WRT_RST_in              : in  std_logic;
      WRT_START_in            : in  std_logic;
      WRT_STANDBY_in          : in  std_logic;
      WRT_STOP_COUNT_VALUE_in : in  std_logic_vector(31 downto 0);
      WRT_out                 : out std_logic;
      WRT_END_COUNT_out       : out std_logic
      );
  end component;

  --!Ricevitore dati di configurazione
  component Config_Receiver is
    port(CR_CLK_in               : in  std_logic;
         CR_RST_in               : in  std_logic;
         CR_FIFO_WAIT_REQUEST_in : in  std_logic;
         CR_DATA_in              : in  std_logic_vector(31 downto 0);
         CR_FWV_in               : in  std_logic_vector(31 downto 0);
         CR_FIFO_READ_EN_out     : out std_logic;
         CR_DATA_out             : out std_logic_vector(31 downto 0);
         CR_ADDRESS_out          : out std_logic_vector(15 downto 0);
         CR_DATA_VALID_out       : out std_logic;
         CR_WARNING_out          : out std_logic_vector(2 downto 0)
         );
  end component;

  --!Banco di registri per i dati di configurazione
  component registerArray is
    port (
      iCLK       : in  std_logic;       --!Main clock
      iRST       : in  std_logic;       --!Main reset
      iCNT       : in  tControlIn;      --!Control input signals
      oCNT       : out tControlOut;     --!Control output flags
      --Register array
      oREG_ARRAY : out tRegArray;       --!Register array
      iHPS_REG   : in  tRegIntf;        --!HPS interface
      iFPGA_REG  : in  tFpgaRegIntf     --!FPGA interface
      );
  end component;

  --!Reads the HK and sends them in a packet
  component hkReader is
    generic(
      pFIFO_WIDTH : natural := 32;      --!FIFO data width
      pPARITY     : string  := "EVEN";  --!Parity polarity ("EVEN" or "ODD")
      pGW_VER     : std_logic_vector(31 downto 0)  --!Firmware version from HoG
      );
    port (
      iCLK        : in  std_logic;      --!Main clock
      iRST        : in  std_logic;      --!Main reset
      iCNT        : in  tControlIn;     --!Control input signals
      oCNT        : out tControlOut;    --!Control output flags
      iINT_START  : in  std_logic;      --!Enable for the internal start
      --Register array
      iREG_ARRAY  : in  tRegArray;      --!Register array input
      --Output FIFO interface
      oFIFO_DATA  : out std_logic_vector(pFIFO_WIDTH-1 downto 0);  --!Fifo Data in
      oFIFO_WR    : out std_logic;      --!Fifo write-request in
      iFIFO_AFULL : in  std_logic       --!Fifo almost-full flag
      );
  end component;

  --!@copydoc CRC32.vhd
  component CRC32 is
    generic(
      pINITIAL_VAL : std_logic_vector(31 downto 0) := x"FFFFFFFF"
      );
    port (
      iCLK    : in  std_logic;          --!Main Clock (used at rising edge)
      iRST    : in  std_logic;          --!Main Reset (synchronous)
      iCRC_EN : in  std_logic;          --!Enable
      iDATA   : in  std_logic_vector (31 downto 0);  --!Input to compute the CRC on
      oCRC    : out std_logic_vector (31 downto 0)   --!CRC32 of the sequence
      );
  end component;

  --!@copydoc HPS_intf.vhd
  component HPS_intf is
    generic (
      pGW_VER : std_logic_vector(31 downto 0)
      );
    port (
      --# {{clocks|Clock}}
      iCLK                : in  std_logic;
      --# {{resets|Reset}}
      iRST                : in  std_logic;
      iRST_REG            : in  std_logic;
      --# {{ConfigRX | ConfigRX}}
      oCR_WARNING         : out std_logic_vector(2 downto 0);
      --# {{HKReader|HKReader}}
      iHK_RDR_CNT         : in  tControlIn;
      iHK_RDR_INT_START   : in  std_logic;
      --# {{F2HFast|F2HFast}}
      iF2HFAST_CNT        : in  tControlIn;
      iF2HFAST_METADATA   : in  tF2hMetadata;
      oF2HFAST_BUSY       : out std_logic;
      oF2HFAST_WARNING    : out std_logic;
      --# {{RegArray|RegArray}}
      iREG_ARRAY          : in  tRegArray;
      oREG_CONFIG_RX      : out tRegIntf;
      --# {{FdiFifo|FdiFifo}}
      iFDI_FIFO           : in  tFifo32Out;
      oFDI_FIFO_RD        : out std_logic;
      --# {{H2F_FIFO|H2F_FIFO}}
      iFIFO_H2F_EMPTY     : in  std_logic;
      iFIFO_H2F_DATA      : in  std_logic_vector(31 downto 0);
      oFIFO_H2F_RE        : out std_logic;
      --# {{F2H_FIFO|F2H_FIFO}}
      iFIFO_F2H_AFULL     : in  std_logic;
      oFIFO_F2H_WE        : out std_logic;
      oFIFO_F2H_DATA      : out std_logic_vector(31 downto 0);
      --# {{F2H_FastFIFO|F2H_FastFIFO}}
      iFIFO_F2HFAST_AFULL : in  std_logic;
      oFIFO_F2HFAST_WE    : out std_logic;
      oFIFO_F2HFAST_DATA  : out std_logic_vector(31 downto 0)  --!F2H Fast q
      );
  end component;


  --!@copydoc FFD.vhd
  --!Unità di base per realizzare gli shift register dei moduli PRBS
  component FFD is
    port(
      iCLK    : in  std_logic;
      iRST    : in  std_logic;
      iENABLE : in  std_logic;
      iD      : in  std_logic;
      oQ      : out std_logic
      );
  end component;

  --!@copydoc PRBS8.vhd
  --!Modulo per la generazione di dati pseudo-casuali a 8 bit
  component PRBS8 is
    port(
      iCLK      : in  std_logic;
      iRST      : in  std_logic;
      iPRBS8_en : in  std_logic;
      oDATA     : out std_logic_vector(7 downto 0)
      );
  end component;

  --!@copydoc PRBS32.vhd
  --!Modulo per la generazione di dati pseudo-casuali a 32 bit
  component PRBS32 is
    port(
      iCLK       : in  std_logic;
      iRST       : in  std_logic;
      iPRBS32_en : in  std_logic;
      oDATA      : out std_logic_vector(31 downto 0)
      );
  end component;

  --!@copydoc Test_Unit.vhd
  --!Unità di test per verificare il funzionamento della sola scheda DAQ
  component Test_Unit is
    port(
      iCLK            : in  std_logic;  -- Porta per il clock
      iRST            : in  std_logic;  -- Porta per il reset
      iEN             : in  std_logic;  -- Porta per l'abilitazione della unità di test
      iSETTING_CONFIG : in  std_logic_vector(1 downto 0);  -- Configurazione modalità operativa: "00"-->dati pseudocasuali generati con un tempo pseudocasuale, "01" dati pseudocasuali generati negli istanti di trigger, "10" dati pseudocasuali generati di continuo (rate massima)
      iSETTING_LENGTH : in  std_logic_vector(31 downto 0);  -- Lunghezza del pacchetto --> Number of 32-bit payload words + 10
      iTRIG           : in  std_logic;  -- Ingresso per il segnale di trigger proveniente dalla trigBusyLogic
      oDATA           : out std_logic_vector(31 downto 0);  -- Numero binario a 32 bit pseudo-casuale
      oDATA_VALID     : out std_logic;  -- Segnale che attesta la validità dei dati in uscita dalla Test_Unit. Se oDATA_VALID=1 --> il valore di "oDATA" è consistente
      oTEST_BUSY      : out std_logic  -- La Test_Unit è impegnata e non può essere interrotta, altrimenti il pacchetto dati verrebbe incompleto
      );
  end component;

  --!@copydoc FastData_Transmitter.vhd
  --!Trasmettitore dei dati scientifici
  component FastData_Transmitter is
    generic(
      pGW_VER : std_logic_vector(31 downto 0)
      );
    port(
      iCLK         : in  std_logic;     -- Clock
      iRST         : in  std_logic;     -- Reset
      -- Enable
      iEN          : in  std_logic;  -- Abilitazione del modulo FastData_Transmitter
      -- Settings Packet
      iMETADATA    : in  tF2hMetadata;  --Packet header information all'FPGA
      -- Fifo Management
      iFIFO_DATA   : in  std_logic_vector(31 downto 0);  -- "Data_Output" della FIFO a monte del FastData_Transmitter
      iFIFO_EMPTY  : in  std_logic;  -- "Empty" della FIFO a monte del FastData_Transmitter
      iFIFO_AEMPTY : in  std_logic;  -- "Almost_Empty" della FIFO a monte del FastData_Transmitter. ATTENZIONE!!!--> Per un corretto funzionamento, impostare pAEMPTY_VAL = 2 sulla FIFO a monte del FastData_Transmitter
      oFIFO_RE     : out std_logic;  -- "Read_Enable" della FIFO a monte del FastData_Transmitter
      oFIFO_DATA   : out std_logic_vector(31 downto 0);  -- "Data_Inutput" della FIFO a valle del FastData_Transmitter
      iFIFO_AFULL  : in  std_logic;  -- "Almost_Full" della FIFO a valle del FastData_Transmitter
      oFIFO_WE     : out std_logic;  -- "Write_Enable" della FIFO a valle del FastData_Transmitter
      -- Output Flag
      oBUSY        : out std_logic;  -- Il trasmettitore è impegnato in un trasferimento dati. '0'-->ok, '1'-->busy
      oWARNING     : out std_logic  -- Malfunzionamenti. '0'-->ok, '1'--> errore: la macchina è finita in uno stato non precisato
      );
  end component;

  --!@copydoc trigBusyLogic.vhd
  component trigBusyLogic is
    port (
      iCLK            : in  std_logic;
      iRST            : in  std_logic;
      iRST_COUNTERS   : in  std_logic;
      iCFG            : in  std_logic_vector(31 downto 0);
      iEXT_TRIG       : in  std_logic;
      iBUSIES_AND     : in  std_logic_vector(7 downto 0);
      iBUSIES_OR      : in  std_logic_vector(7 downto 0);
      oTRIG           : out std_logic;
      oTRIG_ID        : out std_logic_vector(15 downto 0);
      oTRIG_COUNT     : out std_logic_vector(31 downto 0);
      oEXT_TRIG_COUNT : out std_logic_vector(31 downto 0);
      oINT_TRIG_COUNT : out std_logic_vector(31 downto 0);
      oTRIG_WHEN_BUSY : out std_logic_vector(7 downto 0);
      oBUSY           : out std_logic
      );
  end component;

  --!@copydoc TdaqModule.vhd
  component TdaqModule is
    generic (
      pFDI_WIDTH : natural;
      pFDI_DEPTH : natural;
      pGW_VER    : std_logic_vector(31 downto 0)
      );
    port (
      iCLK                : in  std_logic;
      --# {{RegArray|RegArray}}
      iRST                : in  std_logic;
      iRST_COUNT          : in  std_logic;
      iRST_REG            : in  std_logic;
      oREG_ARRAY          : out tRegArray;
      iINT_TS             : in  std_logic_vector(63 downto 0);
      iEXT_TS             : in  std_logic_vector(63 downto 0);
      --# {{TrigBusy|TrigBusy}}
      iEXT_TRIG           : in  std_logic;
      oTRIG               : out std_logic;
      oBUSY               : out std_logic;
      iTRG_BUSIES_AND     : in  std_logic_vector(7 downto 0);
      iTRG_BUSIES_OR      : in  std_logic_vector(7 downto 0);
      --# {{FastDATA-Detector interface|FastDATA-Detector interface}}
      iFASTDATA_DATA      : in  std_logic_vector(cREG_WIDTH-1 downto 0);
      iFASTDATA_WE        : in  std_logic;
      oFASTDATA_AFULL     : out std_logic;
      --# {{H2F_FIFO|H2F_FIFO}}
      iFIFO_H2F_EMPTY     : in  std_logic;
      iFIFO_H2F_DATA      : in  std_logic_vector(31 downto 0);
      oFIFO_H2F_RE        : out std_logic;
      --# {{F2H_FIFO|F2H_FIFO}}
      iFIFO_F2H_AFULL     : in  std_logic;
      oFIFO_F2H_WE        : out std_logic;
      oFIFO_F2H_DATA      : out std_logic_vector(31 downto 0);
      --# {{F2H_FastFIFO|F2H_FastFIFO}}
      iFIFO_F2HFAST_AFULL : in  std_logic;
      oFIFO_F2HFAST_WE    : out std_logic;
      oFIFO_F2HFAST_DATA  : out std_logic_vector(31 downto 0)
      );
  end component;

  --!@copydoc priorityEncoder.vhd
  component priorityEncoder is
    generic (
      pFIFOWIDTH : natural;
      pFIFODEPTH : natural
      );
    port (
      iCLK            : in  std_logic;
      iRST            : in  std_logic;
      --# {{MULTI_FIFO Interface|MULTI_FIFO Interface}}
      iMULTI_FIFO     : in  tMultiAdcFifoOut;
      oMULTI_FIFO     : out tMultiAdcFifoIn;
      --# {{FastDATA Interface|FastDATA Interface}}
      oFASTDATA_DATA  : out std_logic_vector(pFIFOWIDTH-1 downto 0);
      oFASTDATA_WE    : out std_logic;
      iFASTDATA_AFULL : in  std_logic
      );
  end component;


  --!Generatore di segnale PWM
  component Variable_PWM_FSM is
    generic (
      period     : integer;  -- Periodo di conteggio del contatore (che di fatto andrà a definire la frequenza del segnale PWM) espresso in "numero di cicli di clock"
      duty_cycle : integer;  -- Numero di cicli di clock per i quali l'uscita dovrà tenersi "alta"
      neg        : integer;  -- Logica di funzionamento del dispositivo. Se neg=0-->logica normale, se neg=1-->logica negata
      R_vs_F     : integer := 0  -- Parametro che seleziona quali fronti d'onda conteggiare. Se R_vs_F=0--> rising edge, se R_vs_F=1--> falling edge
      );
    port (
      SWITCH            : in  std_logic;  -- Ingresso per abilitare il segnale PWM
      ENABLE_COUNTER    : in  std_logic;  -- Ingresso per abilitare il contatore per la generazione del segnale PWM
      RESET_RF_COUNTER  : in  std_logic;  -- Ingresso per il reset del contatore dei fronti d'onda
      CLK               : in  std_logic;  -- Ingresso del segnale di Clock
      LED               : out std_logic;  -- Uscita del dispositivo
      RISING_LED        : out std_logic;  -- Uscita di segnalazione dei fronti di salita
      FALLING_LED       : out std_logic;  -- Uscita di segnalazione dei fronti di discesa
      RISE_FALL_COUNTER : out std_logic_vector(7 downto 0)  -- Uscita contenente il numero di fronti di salita/discesa rilevati dal detector
      );
  end component;

  --!@copydoc DetectorInterface.vhd
  component DetectorInterface is
    port (
      iCLK            : in  std_logic;
      iRST            : in  std_logic;
      --# {{Controls|Controls}}
      iEN             : in  std_logic;
      iTRIG           : in  std_logic;
      oCNT            : out tControlIntfOut;
      iMSD_CONFIG     : in  msd_config;
      --# {{Detector 0|Detector 0}}
      oFE0            : out tFpga2FeIntf;
      oADC0           : out tFpga2AdcIntf;
      --# {{Detector 1|Detector 1}}
      oFE1            : out tFpga2FeIntf;
      oADC1           : out tFpga2AdcIntf;
      --# {{ADCs Inputs|ADCs Inputs}}
      iMULTI_ADC      : in  tMultiAdc2FpgaIntf;
      --# {{FastDATA Interface|FastDATA Interface}}
      oFASTDATA_DATA  : out std_logic_vector(cREG_WIDTH-1 downto 0);
      oFASTDATA_WE    : out std_logic;
      iFASTDATA_AFULL : in  std_logic
      );
  end component;
  
  --!@copydoc erlangRandomTrigger.vhd
  component erlangRandomTrigger is
  port(
    -- Main
    iCLK            : in std_logic;                       --!Clock
    iRST            : in std_logic;                       --!Reset
    iEN             : in std_logic;                       --!randomTrigger module enable
    -- External Busy
    iEXT_BUSY       : in std_logic;                       --!Ignore trigger
    -- Trigger Property    
    iTHRSH_LEVEL    : in std_logic_vector(31 downto 0);   --!Threshold to generate trigger by randomTrigger module [0 - 12]
    iPULSE_WIDTH    : in std_logic_vector(31 downto 0);   --!Length of the pulse (in number of iCLK cycles)
    iINT_BUSY       : in std_logic_vector(31 downto 0);   --!Ignore trigger for "N" clock cycles after trigger
    iSHAPE_FACTOR   : in std_logic_vector(31 downto 0);   --!Statistic distribution: K=1 -> Exponential, K>7 -> Gaussian
    iFREQ_DIV       : in std_logic_vector(31 downto 0);   --!Period of periodic (in number of iCLK cycles) and comparison frequency for randomTrigger
    -- Output
    oTRIG           : out std_logic;                      --!Trigger
    oSLOW_CLOCK     : out std_logic                       --!Periodic trigger
    );
  end component;
  
  --!@copydoc randomTrigger.vhd
  component randomTrigger is
  port(
    iCLK            : in  std_logic;        --!Main clock
    iRST            : in  std_logic;        --!Main reset
    iEN             : in  std_logic;        --!Enable Comparison between iTHRESHOLD and pseudocasual 32-bit value
    -- External Busy
    iEXT_BUSY       : in std_logic;         --!Ignore trigger
    -- Settings
    iTHRESHOLD      : in std_logic_vector(31 downto 0);  --!Threshold to configure trigger rate (low threshold --> High trigger rate)
    iINT_BUSY       : in std_logic_vector(31 downto 0);  --!Ignore trigger for "N" clock cycles after trigger
    iSHAPER_T_ON    : in std_logic_vector(31 downto 0);  --!Length of the pulse trigger
    iFREQ_DIV       : in std_logic_vector(31 downto 0);  --!Slow clock duration (in number of iCLK cycles) to drive PRBS32
    -- Output
    oTRIG           : out std_logic;   --!Trigger
    oSLOW_CLOCK     : out std_logic    --!PRBS32 enable (or trigger with costant frequency)
    );
  end component;

  -- Functions -----------------------------------------------------------------
  --!@brief Compute the parity bit of an 8-bit data with both polarities
  --!@param[in] p String containing the polarity, "EVEN" or "ODD"
  --!@param[in] d Input 8-bit data
  --!@return  Parity bit of the incoming 8-bit data
  function parity8bit (p : string; d : std_logic_vector(7 downto 0)) return std_logic;

  --!@brief Compute the and between all the elements of a std_logic_vector
  --!@param[in] slv Input std_logic_vector to be reduced to a std_logic
  --!@return  And of all of the slv elements
  function unary_and(slv : in std_logic_vector) return std_logic;

  --!@brief Compute the or between all the elements of a std_logic_vector
  --!@param[in] slv Input std_logic_vector to be reduced to a std_logic
  --!@return  Or of all of the slv elements
  function unary_or(slv : in std_logic_vector) return std_logic;

end paperoPackage;

--!@copydoc paperoPackage.vhd
package body paperoPackage is
  function parity8bit (p : string; d : std_logic_vector(7 downto 0)) return std_logic is
    variable x : std_logic;
  begin
    if p = "ODD" then
      x := not (d(0) xor d(1) xor d(2) xor d(3)
                xor d(4) xor d(5) xor d(6) xor d(7));
    elsif p = "EVEN" then
      x := d(0) xor d(1) xor d(2) xor d(3)
           xor d(4) xor d(5) xor d(6) xor d(7);
    end if;
    return x;
  end function;

  function unary_and(slv : in std_logic_vector) return std_logic is
    variable and_v : std_logic := '1';  -- Null input returns '1'
  begin
    for i in slv'range loop
      and_v := and_v and slv(i);
    end loop;
    return and_v;
  end function;

  function unary_or(slv : in std_logic_vector) return std_logic is
    variable or_v : std_logic := '0';   -- Null input returns '0'
  begin
    for i in slv'range loop
      or_v := or_v or slv(i);
    end loop;
    return or_v;
  end function;

end package body;
