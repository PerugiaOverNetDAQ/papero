--!@file top_papero.vhd
--!brief Top module of the papero FPGA gateware.
--!@details
--!
--!Instantiates HPS, TDAQ module, and ancillary electronics.
--!To add a detector readout:
--! - Connect the detector interface to the fast interface of the TDAQ module
--!  - Add the needed pin to the ports and the papero_pins.qsf file.
--!
--!@todo Add reset to the HPS-FPGA fifos
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it
--!@author Mattia Barbanera, mattia.barbanera@infn.it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.intel_package.all;
use work.paperoPackage.all;
use work.basic_package.all;
use work.FOOTpackage.all;


--!@copydoc top_papero.vhd
entity top_papero is
  generic (
    --HoG: Global Generic Variables
    GLOBAL_DATE : std_logic_vector(31 downto 0) := (others => '0');
    GLOBAL_TIME : std_logic_vector(31 downto 0) := (others => '0');
    GLOBAL_VER  : std_logic_vector(31 downto 0) := (others => '0');
    GLOBAL_SHA  : std_logic_vector(31 downto 0) := (others => '0');
    TOP_VER     : std_logic_vector(31 downto 0) := (others => '0');
    TOP_SHA     : std_logic_vector(31 downto 0) := (others => '0');
    CON_VER     : std_logic_vector(31 downto 0) := (others => '0');
    CON_SHA     : std_logic_vector(31 downto 0) := (others => '0');
    HOG_VER     : std_logic_vector(31 downto 0) := (others => '0');
    HOG_SHA     : std_logic_vector(31 downto 0) := (others => '0');

    --HoG: Project Specific Lists (One for each .src file in your Top/ folder)
    PAPERO_SHA : std_logic_vector(31 downto 0) := (others => '0');
    PAPERO_VER : std_logic_vector(31 downto 0) := (others => '0')
    );
  port(
    --- CLOCK ------------------------------------------------------------------
    FPGA_CLK1_50 : in std_logic;
    FPGA_CLK2_50 : in std_logic;
    FPGA_CLK3_50 : in std_logic;

    --- HPS --------------------------------------------------------------------
    HPS_CONV_USB_N   : inout std_logic;
    HPS_DDR3_ADDR    : out   std_logic_vector(14 downto 0);
    HPS_DDR3_BA      : out   std_logic_vector(2 downto 0);
    HPS_DDR3_CAS_N   : out   std_logic;
    HPS_DDR3_CK_N    : out   std_logic;
    HPS_DDR3_CK_P    : out   std_logic;
    HPS_DDR3_CKE     : out   std_logic;
    HPS_DDR3_CS_N    : out   std_logic;
    HPS_DDR3_DM      : out   std_logic_vector(3 downto 0);
    HPS_DDR3_DQ      : inout std_logic_vector(31 downto 0);
    HPS_DDR3_DQS_N   : inout std_logic_vector(3 downto 0);
    HPS_DDR3_DQS_P   : inout std_logic_vector(3 downto 0);
    HPS_DDR3_ODT     : out   std_logic;
    HPS_DDR3_RAS_N   : out   std_logic;
    HPS_DDR3_RESET_N : out   std_logic;
    HPS_DDR3_RZQ     : in    std_logic;
    HPS_DDR3_WE_N    : out   std_logic;
    HPS_ENET_GTX_CLK : out   std_logic;
    HPS_ENET_INT_N   : inout std_logic;
    HPS_ENET_MDC     : out   std_logic;
    HPS_ENET_MDIO    : inout std_logic;
    HPS_ENET_RX_CLK  : in    std_logic;
    HPS_ENET_RX_DATA : in    std_logic_vector(3 downto 0);
    HPS_ENET_RX_DV   : in    std_logic;
    HPS_ENET_TX_DATA : out   std_logic_vector(3 downto 0);
    HPS_ENET_TX_EN   : out   std_logic;
    HPS_GSENSOR_INT  : inout std_logic;
    HPS_I2C0_SCLK    : inout std_logic;
    HPS_I2C0_SDAT    : inout std_logic;
    HPS_I2C1_SCLK    : inout std_logic;
    HPS_I2C1_SDAT    : inout std_logic;
    HPS_KEY          : inout std_logic;
    HPS_LED          : inout std_logic;
    HPS_LTC_GPIO     : inout std_logic;
    HPS_SD_CLK       : out   std_logic;
    HPS_SD_CMD       : inout std_logic;
    HPS_SD_DATA      : inout std_logic_vector(3 downto 0);
    HPS_SPIM_CLK     : out   std_logic;
    HPS_SPIM_MISO    : in    std_logic;
    HPS_SPIM_MOSI    : out   std_logic;
    HPS_SPIM_SS      : inout std_logic;
    HPS_UART_RX      : in    std_logic;
    HPS_UART_TX      : out   std_logic;
    HPS_USB_CLKOUT   : in    std_logic;
    HPS_USB_DATA     : inout std_logic_vector(7 downto 0);
    HPS_USB_DIR      : in    std_logic;
    HPS_USB_NXT      : in    std_logic;
    HPS_USB_STP      : out   std_logic;

    --- KEY --------------------------------------------------------------------
    KEY : in std_logic_vector(1 downto 0);

    --- LED --------------------------------------------------------------------
    LED : out std_logic_vector(7 downto 0);

    --- SW ---------------------------------------------------------------------
    SW : in std_logic_vector(3 downto 0);

    --- GPIO -------------------------------------------------------------------
    -- HEFs Signals
    oIMON_CONV  : out std_logic_vector(1 downto 0);
    oIMON_SCK : out std_logic_vector(1 downto 0);
    iIMON_SDO : in  std_logic_vector(1 downto 0);
    ioVSET_SDA : inout  std_logic_vector(1 downto 0);
    oVSET_SCL : out std_logic_vector(1 downto 0);
    iADC_DATA_1 : in  std_logic_vector(1 downto 0);
    iADC_DATA_2 : in  std_logic_vector(1 downto 0);
    iADC_DATA_3 : in  std_logic_vector(1 downto 0);
    iADC_DATA_4 : in  std_logic_vector(1 downto 0);
    iADC_DATA_5 : in  std_logic_vector(1 downto 0);
    iADC_DATA_6 : in  std_logic_vector(1 downto 0);
    iADC_DATA_7 : in  std_logic_vector(1 downto 0);
    oADC_CONV : out std_logic_vector(1 downto 0);
    oADC_SCK  : out std_logic_vector(1 downto 0);
    oVA_DRESET  : out std_logic_vector(1 downto 0);
    oVA_HOLDb : out std_logic_vector(1 downto 0);
    oVA_SHIFT_IN  : out std_logic_vector(1 downto 0);
    oVA_CLKb  : out std_logic_vector(1 downto 0);
    -- HEFs Grounds
    iHEF_GND : in  std_logic_vector(35 downto 0);

    --- ARDUINO HEADER ---------------------------------------------------------
    -- Central DAQ
    iCTX_TIME_CLK : in  std_logic;
    iCTX_TIME_RST : in  std_logic;
    iCTX_EXT_TRIG : in  std_logic;
    oCTX_BUSY : out std_logic;
    oCTX_TRIG : out std_logic;
    oCTX_GND  : out  std_logic_vector(6 downto 0);
    iCTX_GND  : out  std_logic_vector(1 downto 0);
    ioCTX_OD  : inout std_logic_vector(2 downto 0)
    );
end entity top_papero;

--!@copydoc top_papero.vhd
architecture std of top_papero is
  constant cCAL_REQUEST_ARM_CYCLES : positive := 4;

  type tRunState is (
    RUN_IDLE,
    RUN_EVENT_ARM,
    RUN_EVENTS,
    RUN_CAL_ARM,
    RUN_CALIBRATION,
    RUN_CAL_DRAIN,
    RUN_WAIT_STOP,
    RUN_STOP_CAL,
    RUN_STOP_DRAIN
  );

  --HPS signals
  signal hps_fpga_reset_n       : std_logic;
  signal fpga_debounced_buttons : std_logic_vector(1 downto 0);
  signal fpga_led_internal      : std_logic_vector(6 downto 0);
  signal hps_reset_req          : std_logic_vector(2 downto 0);
  signal hps_cold_reset         : std_logic;
  signal hps_warm_reset         : std_logic;
  signal hps_debug_reset        : std_logic;
  signal stm_hw_events          : std_logic_vector(27 downto 0);
  signal fpga_clk_50            : std_logic;
  signal sRegAddrPio            : std_logic_vector(31 downto 0);
  signal sRegContentPio         : std_logic_vector(31 downto 0);
  signal sRegAddrInt, sRegAddrSyn : std_logic_vector(31 downto 0);
  signal sRegContentInt, sRegContentSyn : std_logic_vector(31 downto 0);

  -- Auxiliaries
  signal fpga_debounced_buttons_n : std_logic_vector(1 downto 0);  -- debounced_bottons (positive logic)
  signal hps_fpga_reset_n_synch   : std_logic;  -- Reset (positive logic)
  signal hps_cold_rst_n           : std_logic;
  signal hps_warm_rst_n           : std_logic;
  signal hps_debug_rst_n          : std_logic;
  signal sClk                     : std_logic;  -- FPGA clock
  signal h2f_clk_50MHz            : std_logic;  -- user clock (50 MHz) from HPS
  signal h2f_clk_96MHz            : std_logic;  -- user clock (96 MHz) from HPS

  -- Scientific data fifo FPGA --> HPS
  signal fast_fifo_f2h_data_in      : std_logic_vector(31 downto 0);  -- Data
  signal fast_fifo_f2h_wr_en        : std_logic;  -- Write Enable
  signal fast_fifo_f2h_full         : std_logic;  -- Fifo Full
  signal fast_fifo_f2h_afull        : std_logic;  -- Fifo Almost Full
  signal fast_fifo_f2h_addr_csr     : std_logic_vector(2 downto 0);
  signal fast_fifo_f2h_rd_en_csr    : std_logic;
  signal fast_fifo_f2h_data_in_csr  : std_logic_vector(31 downto 0);
  signal fast_fifo_f2h_wr_en_csr    : std_logic;
  signal fast_fifo_f2h_data_out_csr : std_logic_vector(31 downto 0);

  -- Telemetry fifo FPGA --> HPS
  signal fifo_f2h_data_in      : std_logic_vector(31 downto 0);  -- Data
  signal fifo_f2h_wr_en        : std_logic;  -- Write Enable
  signal fifo_f2h_full         : std_logic;  -- Fifo Full
  signal fifo_f2h_afull        : std_logic;  -- Fifo Almost Full
  signal fifo_f2h_addr_csr     : std_logic_vector(2 downto 0);
  signal fifo_f2h_rd_en_csr    : std_logic;
  signal fifo_f2h_data_in_csr  : std_logic_vector(31 downto 0);
  signal fifo_f2h_wr_en_csr    : std_logic;
  signal fifo_f2h_data_out_csr : std_logic_vector(31 downto 0);

  -- Configuration fifo HPS --> FPGA
  signal fifo_h2f_data_out     : std_logic_vector(31 downto 0);  -- Data
  signal fifo_h2f_rd_en        : std_logic;                      -- Read Enable
  signal fifo_h2f_empty        : std_logic;                      -- Fifo Empty
  signal fifo_h2f_addr_csr     : std_logic_vector(2 downto 0);
  signal fifo_h2f_rd_en_csr    : std_logic;
  signal fifo_h2f_data_in_csr  : std_logic_vector(31 downto 0);
  signal fifo_h2f_wr_en_csr    : std_logic;
  signal fifo_h2f_data_out_csr : std_logic_vector(31 downto 0);

  -- TDAQ Module
  signal sExtTrigSynch : std_logic;
  signal sMainTrig     : std_logic;
  signal sMainBusy     : std_logic;
  signal sTrgBusiesAnd : std_logic_vector(7 downto 0);
  signal sTrgBusiesOr  : std_logic_vector(7 downto 0);
  signal sRegArray     : tRegArray;

  -- Timestamps
  signal sIntTsEn    : std_logic;
  signal sIntTsRst   : std_logic;
  signal sIntTsCount : std_logic_vector(63 downto 0);
  signal sExtTsEn    : std_logic;
  signal sExtTsRst   : std_logic;
  signal sExtTsCount : std_logic_vector(63 downto 0);

  -- HV DACs and ADCs
  signal sbiasStart : std_logic;
  signal sBiasButtonSynch : std_logic;
  signal sHvRqt : std_logic_vector(1 downto 0);
  signal sHvRqtPrev : std_logic_vector(1 downto 0);
  signal sHvAck : std_logic_vector(1 downto 0);
  signal sHvErr : std_logic_vector(1 downto 0);
  signal sHvMon : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sHvValue0 : std_logic_vector(9 downto 0);
  signal sHvValue1 : std_logic_vector(9 downto 0);

  signal sBiasCurrentStart  : std_logic;
  signal sBiasCurrentConv   : std_logic;
  signal sBiasCurrentSck    : std_logic;
  signal sBiasCurrentSdo    : std_logic_vector(cLTC2312_ADCS-1 downto 0);
  signal sBiasCurrent       : tLtc2312OutPort;
  signal sBiasCurrWr        : std_logic;

  --Detector interface
  signal sDetIntfRst    : std_logic;
  signal sDetIntfEn     : std_logic;
  signal sDetIntfCntOut : tControlIntfOut;
  signal sDetIntfCfg    : msd_config;
  signal sDetIntfQ      : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sDetIntfWe     : std_logic;
  signal sDetIntfAfull  : std_logic;
  -- Matadata associato al payload reale
  signal sPacketValid   : std_logic;
  signal sPayloadWords  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sPacketTrigType : std_logic_vector(7 downto 0);
  signal sInjectData    : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sInjectStatus  : std_logic_vector(cREG_WIDTH-1 downto 0);
  signal sInjectWe      : std_logic;
  signal sInjectClear   : std_logic;
  signal sInjectEnd     : std_logic;
  signal sInjectRequested : std_logic;
  signal sFeA           : tFpga2FeIntf;
  signal sFeB           : tFpga2FeIntf;
  signal sAdcA          : tFpga2AdcIntf;
  signal sAdcB          : tFpga2AdcIntf;
  signal sMultiAdc      : tMultiAdc2FpgaIntf;

  signal sCountersRst   : std_logic;
  signal sRegArrayRst   : std_logic;
  signal sRunMode       : std_logic;
  signal sStartPrev     : std_logic;
  signal sThrApplyPending : std_logic;
  signal sThrValid      : std_logic;
  signal sLTH           : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sHTH           : std_logic_vector(cADC_DATA_WIDTH-1 downto 0);
  signal sDaqMode       : std_logic_vector(1 downto 0);
  signal sDetectorDaqMode : std_logic_vector(1 downto 0);
  signal sEventEnable   : std_logic;
  signal sCommandHold   : std_logic;
  signal sTdaqDataIdle  : std_logic;
  signal sCalEnable     : std_logic;
  signal sCalDump       : std_logic;
  signal sCalSave       : std_logic;
  signal sCalAbort      : std_logic;
  signal sCalibValid    : std_logic;
  signal sCalibDone     : std_logic;
  signal sCalibTrigReady : std_logic;
  signal sCalOperationDump : std_logic;
  signal sCalibrationRun : std_logic;
  signal sDetectorPipelineIdle : std_logic;
  signal sDrainIdleSeen : std_logic;
  signal sCalDoneLatched : std_logic;
  signal sRunIdleStatus : std_logic;
  signal sCalArmCounter : natural range 0 to cCAL_REQUEST_ARM_CYCLES-1;
  signal sRunState      : tRunState;

  signal sMultiAdcSynch : tMultiAdc2FpgaIntf;
  signal sBcoClkSynch   : std_logic;
  signal sBcoRstReplica : std_logic;
  signal sBcoRstSynch   : std_logic;
  signal sBusy          : std_logic;
  signal sErrors        : std_logic;
  signal sDebug         : std_logic_vector(7 downto 0);

begin
  -- connection of internal logics ----------------------------
  fpga_clk_50   <= FPGA_CLK1_50;
  sClk          <= h2f_clk_50MHz;
  stm_hw_events <= "000000000000000" & SW & fpga_led_internal & fpga_debounced_buttons;
  
  LED(7 downto 4) <= (others => '0');

  fpga_debounced_buttons_n <= not fpga_debounced_buttons;  --FPGA buttons work in negated logic, opposite to the internal modules

  hps_cold_rst_n  <= not hps_cold_reset;
  hps_warm_rst_n  <= not hps_warm_reset;
  hps_debug_rst_n <= not hps_debug_reset;
  --!@brief HPS instance
  --!@todo Are clock 50MHz and clock 96MHz inverted?
  SoC_inst : soc_system port map (
    --Clock&Reset
    clk_clk                               => fpga_clk_50,  -- clk.clk
    reset_reset_n                         => hps_fpga_reset_n,  -- reset.reset_n
    --HPS ddr3
    memory_mem_a                          => HPS_DDR3_ADDR,  --  memory.mem_a
    memory_mem_ba                         => HPS_DDR3_BA,  -- .mem_ba
    memory_mem_ck                         => HPS_DDR3_CK_P,  -- .mem_ck
    memory_mem_ck_n                       => HPS_DDR3_CK_N,  -- .mem_ck_n
    memory_mem_cke                        => HPS_DDR3_CKE,  -- .mem_cke
    memory_mem_cs_n                       => HPS_DDR3_CS_N,  -- .mem_cs_n
    memory_mem_ras_n                      => HPS_DDR3_RAS_N,  -- .mem_ras_n
    memory_mem_cas_n                      => HPS_DDR3_CAS_N,  -- .mem_cas_n
    memory_mem_we_n                       => HPS_DDR3_WE_N,  -- .mem_we_n
    memory_mem_reset_n                    => HPS_DDR3_RESET_N,  -- .mem_reset_n
    memory_mem_dq                         => HPS_DDR3_DQ,  -- .mem_dq
    memory_mem_dqs                        => HPS_DDR3_DQS_P,  -- .mem_dqs
    memory_mem_dqs_n                      => HPS_DDR3_DQS_N,  -- .mem_dqs_n
    memory_mem_odt                        => HPS_DDR3_ODT,  -- .mem_odt
    memory_mem_dm                         => HPS_DDR3_DM,  -- .mem_dm
    memory_oct_rzqin                      => HPS_DDR3_RZQ,  -- .oct_rzqin
    --HPS ethernet
    hps_0_hps_io_hps_io_emac1_inst_TX_CLK => HPS_ENET_GTX_CLK,  -- hps_0_hps_io.hps_io_emac1_inst_TX_CLK
    hps_0_hps_io_hps_io_emac1_inst_TXD0   => HPS_ENET_TX_DATA(0),  -- .hps_io_emac1_inst_TXD0
    hps_0_hps_io_hps_io_emac1_inst_TXD1   => HPS_ENET_TX_DATA(1),  -- .hps_io_emac1_inst_TXD1
    hps_0_hps_io_hps_io_emac1_inst_TXD2   => HPS_ENET_TX_DATA(2),  -- .hps_io_emac1_inst_TXD2
    hps_0_hps_io_hps_io_emac1_inst_TXD3   => HPS_ENET_TX_DATA(3),  -- .hps_io_emac1_inst_TXD3
    hps_0_hps_io_hps_io_emac1_inst_RXD0   => HPS_ENET_RX_DATA(0),  -- .hps_io_emac1_inst_RXD0
    hps_0_hps_io_hps_io_emac1_inst_MDIO   => HPS_ENET_MDIO,  -- .hps_io_emac1_inst_MDIO
    hps_0_hps_io_hps_io_emac1_inst_MDC    => HPS_ENET_MDC,  -- .hps_io_emac1_inst_MDC
    hps_0_hps_io_hps_io_emac1_inst_RX_CTL => HPS_ENET_RX_DV,  -- .hps_io_emac1_inst_RX_CTL
    hps_0_hps_io_hps_io_emac1_inst_TX_CTL => HPS_ENET_TX_EN,  -- .hps_io_emac1_inst_TX_CTL
    hps_0_hps_io_hps_io_emac1_inst_RX_CLK => HPS_ENET_RX_CLK,  -- .hps_io_emac1_inst_RX_CLK
    hps_0_hps_io_hps_io_emac1_inst_RXD1   => HPS_ENET_RX_DATA(1),  -- .hps_io_emac1_inst_RXD1
    hps_0_hps_io_hps_io_emac1_inst_RXD2   => HPS_ENET_RX_DATA(2),  -- .hps_io_emac1_inst_RXD2
    hps_0_hps_io_hps_io_emac1_inst_RXD3   => HPS_ENET_RX_DATA(3),  -- .hps_io_emac1_inst_RXD3
    --HPS SD card
    hps_0_hps_io_hps_io_sdio_inst_CMD     => HPS_SD_CMD,  -- .hps_io_sdio_inst_CMD
    hps_0_hps_io_hps_io_sdio_inst_D0      => HPS_SD_DATA(0),  -- .hps_io_sdio_inst_D0
    hps_0_hps_io_hps_io_sdio_inst_D1      => HPS_SD_DATA(1),  -- .hps_io_sdio_inst_D1
    hps_0_hps_io_hps_io_sdio_inst_CLK     => HPS_SD_CLK,  -- .hps_io_sdio_inst_CLK
    hps_0_hps_io_hps_io_sdio_inst_D2      => HPS_SD_DATA(2),  -- .hps_io_sdio_inst_D2
    hps_0_hps_io_hps_io_sdio_inst_D3      => HPS_SD_DATA(3),  -- .hps_io_sdio_inst_D3
    --HPS USB
    hps_0_hps_io_hps_io_usb1_inst_D0      => HPS_USB_DATA(0),  -- .hps_io_usb1_inst_D0
    hps_0_hps_io_hps_io_usb1_inst_D1      => HPS_USB_DATA(1),  -- .hps_io_usb1_inst_D1
    hps_0_hps_io_hps_io_usb1_inst_D2      => HPS_USB_DATA(2),  -- .hps_io_usb1_inst_D2
    hps_0_hps_io_hps_io_usb1_inst_D3      => HPS_USB_DATA(3),  -- .hps_io_usb1_inst_D3
    hps_0_hps_io_hps_io_usb1_inst_D4      => HPS_USB_DATA(4),  -- .hps_io_usb1_inst_D4
    hps_0_hps_io_hps_io_usb1_inst_D5      => HPS_USB_DATA(5),  -- .hps_io_usb1_inst_D5
    hps_0_hps_io_hps_io_usb1_inst_D6      => HPS_USB_DATA(6),  -- .hps_io_usb1_inst_D6
    hps_0_hps_io_hps_io_usb1_inst_D7      => HPS_USB_DATA(7),  -- .hps_io_usb1_inst_D7
    hps_0_hps_io_hps_io_usb1_inst_CLK     => HPS_USB_CLKOUT,  -- .hps_io_usb1_inst_CLK
    hps_0_hps_io_hps_io_usb1_inst_STP     => HPS_USB_STP,  -- .hps_io_usb1_inst_STP
    hps_0_hps_io_hps_io_usb1_inst_DIR     => HPS_USB_DIR,  -- .hps_io_usb1_inst_DIR
    hps_0_hps_io_hps_io_usb1_inst_NXT     => HPS_USB_NXT,  -- .hps_io_usb1_inst_NXT
    --HPS SPI
    hps_0_hps_io_hps_io_spim1_inst_CLK    => HPS_SPIM_CLK,  -- .hps_io_spim1_inst_CLK
    hps_0_hps_io_hps_io_spim1_inst_MOSI   => HPS_SPIM_MOSI,  -- .hps_io_spim1_inst_MOSI
    hps_0_hps_io_hps_io_spim1_inst_MISO   => HPS_SPIM_MISO,  -- .hps_io_spim1_inst_MISO
    hps_0_hps_io_hps_io_spim1_inst_SS0    => HPS_SPIM_SS,  -- .hps_io_spim1_inst_SS0
    --HPS UART
    hps_0_hps_io_hps_io_uart0_inst_RX     => HPS_UART_RX,  -- .hps_io_uart0_inst_RX
    hps_0_hps_io_hps_io_uart0_inst_TX     => HPS_UART_TX,  -- .hps_io_uart0_inst_TX
    --HPS I2C1
    hps_0_hps_io_hps_io_i2c0_inst_SDA     => HPS_I2C0_SDAT,  -- .hps_io_i2c0_inst_SDA
    hps_0_hps_io_hps_io_i2c0_inst_SCL     => HPS_I2C0_SCLK,  -- .hps_io_i2c0_inst_SCL
    --HPS I2C2
    hps_0_hps_io_hps_io_i2c1_inst_SDA     => HPS_I2C1_SDAT,  -- .hps_io_i2c1_inst_SDA
    hps_0_hps_io_hps_io_i2c1_inst_SCL     => HPS_I2C1_SCLK,  -- .hps_io_i2c1_inst_SCL
    --GPIO
    hps_0_hps_io_hps_io_gpio_inst_GPIO09  => HPS_CONV_USB_N,  -- .hps_io_gpio_inst_GPIO09
    hps_0_hps_io_hps_io_gpio_inst_GPIO35  => HPS_ENET_INT_N,  -- .hps_io_gpio_inst_GPIO35
    hps_0_hps_io_hps_io_gpio_inst_GPIO40  => HPS_LTC_GPIO,  -- .hps_io_gpio_inst_GPIO40
    hps_0_hps_io_hps_io_gpio_inst_GPIO53  => HPS_LED,  -- .hps_io_gpio_inst_GPIO53
    hps_0_hps_io_hps_io_gpio_inst_GPIO54  => HPS_KEY,  -- .hps_io_gpio_inst_GPIO54
    hps_0_hps_io_hps_io_gpio_inst_GPIO61  => HPS_GSENSOR_INT,  -- .hps_io_gpio_inst_GPIO61
    --FPGA Partion
    led_pio_external_connection_export    => fpga_led_internal,  -- led_pio_external_connection.export
    dipsw_pio_external_connection_export  => SW,  -- dipsw_pio_external_connection.export
    button_pio_external_connection_export => fpga_debounced_buttons,  -- button_pio_external_connection.export
    hps_0_h2f_reset_reset_n               => hps_fpga_reset_n,  -- hps_0_h2f_reset.reset_n
    hps_0_f2h_cold_reset_req_reset_n      => hps_cold_rst_n,  -- hps_0_f2h_cold_reset_req.reset_n
    hps_0_f2h_debug_reset_req_reset_n     => hps_debug_rst_n,  -- hps_0_f2h_debug_reset_req.reset_n
    hps_0_f2h_stm_hw_events_stm_hwevents  => stm_hw_events,  -- hps_0_f2h_stm_hw_events.stm_hwevents
    hps_0_f2h_warm_reset_req_reset_n      => hps_warm_rst_n,  -- hps_0_f2h_warm_reset_req.reset_n
    hps_0_h2f_user0_clock_clk             => h2f_clk_96MHz,  -- hps_0_h2f_user0_clock.clk
    hps_0_h2f_user1_clock_clk             => h2f_clk_50MHz,  -- hps_0_h2f_user1_clock.clk
    --
    regcontent_pio_export                 => sRegContentPio, -- regcontent_pio.export
    regaddr_pio_export                    => sRegAddrPio,    --    regaddr_pio.export
    --Fifo Partion
    fast_fifo_fpga_to_hps_clk_clk          => sClk,  -- fast_fifo_fpga_to_hps_clk.clk
    fast_fifo_fpga_to_hps_rst_reset_n      => '1',  -- fast_fifo_fpga_to_hps_rst.reset_n
    fast_fifo_fpga_to_hps_in_writedata     => fast_fifo_f2h_data_in,  --       fifo_fpga_to_hps_in.writedata
    fast_fifo_fpga_to_hps_in_write         => fast_fifo_f2h_wr_en,  --                          .write
    fast_fifo_fpga_to_hps_in_waitrequest   => fast_fifo_f2h_full,  --                          .waitrequest
    fast_fifo_fpga_to_hps_in_csr_address   => fast_fifo_f2h_addr_csr,  --   fifo_fpga_to_hps_in_csr.address
    fast_fifo_fpga_to_hps_in_csr_read      => fast_fifo_f2h_rd_en_csr,  --                          .read
    fast_fifo_fpga_to_hps_in_csr_writedata => fast_fifo_f2h_data_in_csr,  --                          .writedata
    fast_fifo_fpga_to_hps_in_csr_write     => fast_fifo_f2h_wr_en_csr,  --                          .write
    fast_fifo_fpga_to_hps_in_csr_readdata  => fast_fifo_f2h_data_out_csr,  --                          .readdata

    fifo_fpga_to_hps_clk_clk          => sClk,  --         fifo_fpga_to_hps_clk.clk
    fifo_fpga_to_hps_rst_reset_n      => '1',  --         fifo_fpga_to_hps_rst.reset_n
    fifo_fpga_to_hps_in_writedata     => fifo_f2h_data_in,  --     fast_fifo_fpga_to_hps_in.writedata
    fifo_fpga_to_hps_in_write         => fifo_f2h_wr_en,  --                             .write
    fifo_fpga_to_hps_in_waitrequest   => fifo_f2h_full,  --                             .waitrequest
    fifo_fpga_to_hps_in_csr_address   => fifo_f2h_addr_csr,  -- fast_fifo_fpga_to_hps_in_csr.address
    fifo_fpga_to_hps_in_csr_read      => fifo_f2h_rd_en_csr,  --                             .read
    fifo_fpga_to_hps_in_csr_writedata => fifo_f2h_data_in_csr,  --                             .writedata
    fifo_fpga_to_hps_in_csr_write     => fifo_f2h_wr_en_csr,  --                             .write
    fifo_fpga_to_hps_in_csr_readdata  => fifo_f2h_data_out_csr,  --                             .readdata

    fifo_hps_to_fpga_clk_clk           => sClk,  --    fifo_hps_to_fpga_clk.clk
    fifo_hps_to_fpga_rst_reset_n       => '1',  --    fifo_hps_to_fpga_rst.reset_n
    fifo_hps_to_fpga_out_readdata      => fifo_h2f_data_out,  --     fifo_fpga_to_hps_in.writedata
    fifo_hps_to_fpga_out_read          => fifo_h2f_rd_en,  --                        .write
    fifo_hps_to_fpga_out_waitrequest   => fifo_h2f_empty,  --                        .waitrequest
    fifo_hps_to_fpga_out_csr_address   => fifo_h2f_addr_csr,  -- fifo_fpga_to_hps_in_csr.address
    fifo_hps_to_fpga_out_csr_read      => fifo_h2f_rd_en_csr,  --                        .read
    fifo_hps_to_fpga_out_csr_writedata => fifo_h2f_data_in_csr,  --                        .writedata
    fifo_hps_to_fpga_out_csr_write     => fifo_h2f_wr_en_csr,  --                        .write
    fifo_hps_to_fpga_out_csr_readdata  => fifo_h2f_data_out_csr  --                        .readdata
    );

  --!@brief Debounce logic to clean out glitches within 1ms
  debounce_inst : debounce
    generic map(
      WIDTH         => 2,
      POLARITY      => "LOW",
      TIMEOUT       => 50000,  -- at 50Mhz this is a debounce time of 1ms
      TIMEOUT_WIDTH => 16               -- ceil(log2(TIMEOUT))
      )
    port map (
      clk      => fpga_clk_50,
      reset_n  => hps_fpga_reset_n,
      data_in  => KEY,
      data_out => fpga_debounced_buttons
      );

  --!@brief Source/Probe megawizard instance
  hps_reset_inst : hps_reset
    port map(
      probe      => '0',
      source_clk => fpga_clk_50,
      source     => hps_reset_req
      );

  --!@brief Edge detector
  pulse_cold_reset : altera_edge_detector
    generic map(
      PULSE_EXT             => 6,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 1
      )
    port map (
      clk       => fpga_clk_50,
      rst_n     => hps_fpga_reset_n,
      signal_in => hps_reset_req(0),
      pulse_out => hps_cold_reset
      );

  --!@brief Edge detector
  pulse_warm_reset : altera_edge_detector
    generic map (
      PULSE_EXT             => 2,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 1
      )
    port map (
      clk       => fpga_clk_50,
      rst_n     => hps_fpga_reset_n,
      signal_in => hps_reset_req(1),
      pulse_out => hps_warm_reset
      );

  --!@brief Edge detector
  pulse_debug_reset : altera_edge_detector
    generic map(
      PULSE_EXT             => 32,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 1
      )
    port map (
      clk       => fpga_clk_50,
      rst_n     => hps_fpga_reset_n,
      signal_in => hps_reset_req(2),
      pulse_out => hps_debug_reset
      );

  --!@brief synchronize the reset to the FPGA-side clock
  HPS_RST_SYNCH : sync_stage
    generic map (
      pSTAGES => 3
      )
    port map (
      iCLK => sClk,
      iRST => '0',
      iD   => hps_fpga_reset_n,
      oQ   => hps_fpga_reset_n_synch
      );

  RegAddrSync_proc : process (sClk)
  begin
    if (rising_edge(sClk)) then
      sRegAddrInt <= sRegAddrPio;
      sRegAddrSyn <= sRegAddrInt;
    end if;
  end process RegAddrSync_proc;

  RegContSync_proc : process (fpga_clk_50)
  begin
    if (rising_edge(fpga_clk_50)) then
      sRegContentInt <= sRegArray(slv2int(sRegAddrSyn(ceil_log2(cREGISTERS)-1 downto 0)));
      sRegContentPio <= sRegContentInt;
    end if;
  end process RegContSync_proc;

  -- Continuosly read the level_fifo of FIFO HK
  fifo_f2h_addr_csr  <= "000"; -- fast_fifo_f2h_data_out_csr = Level_Fifo
  fifo_f2h_rd_en_csr <= '1';   -- Update usedw at every clock cycle
  --!@brief Generate the Almost Full of the F2H housekeeping FIFO with the csr
  F2H_HK_AFull_proc : process (fifo_f2h_data_out_csr)
  begin
    if (fifo_f2h_data_out_csr > cF2H_AFULL - 1) then
      fifo_f2h_afull <= '1';
    else
      fifo_f2h_afull <= '0';
    end if;
  end process;

  -- Continuosly read the level_fifo of FIFO Fast_Data
  fast_fifo_f2h_addr_csr  <= "000"; -- fast_fifo_f2h_data_out_csr = Level_Fifo
  fast_fifo_f2h_rd_en_csr <= '1';   -- Update usedw at every clock cycle
  --!@brief Generate the Almost Full of the F2H Fast-Data FIFO with the csr
  F2H_Scientific_AFull_proc : process (fast_fifo_f2h_data_out_csr)
  begin
    if (fast_fifo_f2h_data_out_csr > cFastF2H_AFULL) then
      fast_fifo_f2h_afull <= '1';
    else
      fast_fifo_f2h_afull <= '0';
    end if;
  end process;

  sIntTsEn  <= '1';
  sIntTsRst <= sCountersRst or sDetIntfRst
               or not sRunMode;
  --!@brief Internal timestamp counter
  intTimestampCounter : counter
    generic map (
      pOVERLAP  => "Y",
      pBUSWIDTH => 64
      )
    port map (
      iCLK   => sClk,
      iEN    => sIntTsEn,
      iRST   => sIntTsRst,
      iLOAD  => '0',
      iDATA  => (others => '0'),
      oCOUNT => sIntTsCount
      );

  sExtTsEn  <= sBcoClkSynch;
  sExtTsRst <= sBcoRstSynch or sCountersRst
               or sDetIntfRst or not sRunMode;
  --!@brief External timestamp counter
  extTimestampCounter : counter
    generic map (
      pOVERLAP  => "Y",
      pBUSWIDTH => 64
      )
    port map (
      iCLK   => sClk,
      iEN    => sExtTsEn,
      iRST   => sExtTsRst,
      iLOAD  => '0',
      iDATA  => (others => '0'),
      oCOUNT => sExtTsCount
      );

  --!@brief Wrapper for all of the Trigger and Data Acquisition modules
  sTrgBusiesAnd   <= (others => '0');
  -- Blocca temporaneamente nuovi trigger tramite la normale catena dei busy,
  -- senza resettare la FIFO metadati
  sTrgBusiesOr    <= (0 => sDetIntfCntOut.busy,
                      1 => sDetIntfAfull,
                      2 => sCommandHold,
                      3 => sCalibrationRun and not sCalOperationDump and not sCalibTrigReady,
                      others => '0');

  TdaqModule_i : TdaqModule
    generic map (
      pFDI_WIDTH => cFDI_WIDTH,
      pFDI_DEPTH => cFDI_DEPTH,
      pGW_VER    => PAPERO_SHA
      )
    port map (
      iCLK                => sClk,
      --
      iRST                => sDetIntfRst,
      iRST_COUNT          => sCountersRst,
      iRST_REG            => sRegArrayRst,
      oREG_ARRAY          => sRegArray,
      iINT_TS             => sIntTsCount,
      iEXT_TS             => sExtTsCount,
      iHV_MON             => sHvMon,
      --
      iEXT_TRIG           => sExtTrigSynch,
      iTRIG_ENABLE        => sRunMode,
      iCALIBRATION_ACTIVE => sCalibrationRun,
      iCALIB_VALID        => sCalibValid,
      iRUN_IDLE           => sRunIdleStatus,
      oTRIG               => sMainTrig,
      oBUSY               => sMainBusy,
      oDATA_IDLE          => sTdaqDataIdle,
      iTRG_BUSIES_AND     => sTrgBusiesAnd,
      iTRG_BUSIES_OR      => sTrgBusiesOr,
      --
      iFASTDATA_DATA      => sDetIntfQ,
      iFASTDATA_WE        => sDetIntfWe,
      oFASTDATA_AFULL     => sDetIntfAfull,
      iPACKET_VALID       => sPacketValid,
      iPAYLOAD_WORDS      => sPayloadWords,
      iTRIG_TYPE          => sPacketTrigType,
      oINJECT_DATA        => sInjectData,
      oINJECT_WE          => sInjectWe,
      oINJECT_CLEAR       => sInjectClear,
      oINJECT_END         => sInjectEnd,
      iINJECT_STATUS      => sInjectStatus,
      --
      iFIFO_H2F_EMPTY     => fifo_h2f_empty,
      iFIFO_H2F_DATA      => fifo_h2f_data_out,
      oFIFO_H2F_RE        => fifo_h2f_rd_en,
      --
      iFIFO_F2H_AFULL     => fifo_f2h_afull,
      oFIFO_F2H_WE        => fifo_f2h_wr_en,
      oFIFO_F2H_DATA      => fifo_f2h_data_in,
      --
      iFIFO_F2HFAST_AFULL => fast_fifo_f2h_afull,
      oFIFO_F2HFAST_WE    => fast_fifo_f2h_wr_en,
      oFIFO_F2HFAST_DATA  => fast_fifo_f2h_data_in
      );

  --!@brief Generate reset pulse for register array
  pulse_detIntf_reset : altera_edge_detector
    generic map(
      PULSE_EXT             => 5,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 0
      )
    port map (
      clk       => sClk,
      rst_n     => hps_fpga_reset_n_synch,
      signal_in => sRegArray(rGOTO_STATE)(0),
      pulse_out => sDetIntfRst
      );
  --!@brief Generate reset pulse for register array
  pulse_counters_reset : altera_edge_detector
    generic map(
      PULSE_EXT             => 1,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 0
      )
    port map (
      clk       => sClk,
      rst_n     => hps_fpga_reset_n_synch,
      signal_in => sRegArray(rGOTO_STATE)(1),
      pulse_out => sCountersRst
      );
  --!@brief Generate reset pulse for register array
  pulse_regArray_reset : altera_edge_detector
    generic map(
      PULSE_EXT             => 5,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 0
      )
    port map (
      clk       => sClk,
      rst_n     => hps_fpga_reset_n_synch,
      signal_in => sRegArray(rGOTO_STATE)(2),
      pulse_out => sRegArrayRst
      );
      
  sDetIntfEn               <= not sRegArray(rUNITS_EN)(1);
  sDetIntfCfg.feClkDuty    <= sRegArray(rFE_CLK_PARAM)(31 downto 16);
  sDetIntfCfg.feClkDiv     <= sRegArray(rFE_CLK_PARAM)(15 downto 0);
  sDetIntfCfg.adcClkDuty   <= sRegArray(rADC_CLK_PARAM)(31 downto 16);
  sDetIntfCfg.adcClkDiv    <= sRegArray(rADC_CLK_PARAM)(15 downto 0);
  sDetIntfCfg.cfgPlane     <= sRegArray(rMSD_PARAM)(31 downto 16);
  sDetIntfCfg.intTrgPeriod <= (others => '0');
  sDetIntfCfg.trg2Hold     <= sRegArray(rMSD_PARAM)(15 downto 0);
  sDetIntfCfg.extendBusy   <= sRegArray(rBUSYADC_PARAM)(31 downto 16);
  sDetIntfCfg.adcDelay     <= sRegArray(rBUSYADC_PARAM)(15 downto 0);


  -- Impulso singolo per applicare LTH e HTH
  sThrValid <= sThrApplyPending;

  -- Forza LW come path di uscita dati se calibrationRun è ad 1. Potevo impostare anche 10 o 11. Basta non LEG 00
  sDetectorDaqMode <= "01" when sCalibrationRun = '1' else sDaqMode;
  sRunIdleStatus <= '1' when sRunState = RUN_IDLE and sRunMode = '0' else '0';

  REGISTER_COMMAND_PROC : process(sClk)
  begin
    if rising_edge(sClk) then
      if hps_fpga_reset_n_synch = '0' then
        sStartPrev        <= '0';
        sThrApplyPending  <= '0';
        sLTH              <= cLTH;
        sHTH              <= cHTH;
        sDaqMode          <= "00";
        sEventEnable      <= '0';
        sRunMode          <= '0';
        sCommandHold      <= '0';
        sCalEnable        <= '0';
        sCalDump          <= '0';
        sCalSave          <= '0';
        sCalAbort         <= '0';
        sCalOperationDump <= '0';
        sCalibrationRun   <= '0';
        sCalArmCounter    <= 0;
        sDrainIdleSeen    <= '0';
        sCalDoneLatched   <= '0';
        sInjectRequested  <= '0';
        sRunState         <= RUN_IDLE;

      elsif sRegArrayRst = '1' then
        sStartPrev        <= '0';
        sThrApplyPending  <= '1';
        sLTH              <= cLTH;
        sHTH              <= cHTH;
        sDaqMode          <= "00";
        sEventEnable      <= '0';
        sRunMode          <= '0';
        sCommandHold      <= '0';
        sCalEnable        <= '0';
        sCalDump          <= '0';
        sCalSave          <= '0';
        sCalAbort         <= '0';
        sCalOperationDump <= '0';
        sCalibrationRun   <= '0';
        sCalArmCounter    <= 0;
        sDrainIdleSeen    <= '0';
        sCalDoneLatched   <= '0';
        sInjectRequested  <= '0';
        sRunState         <= RUN_IDLE;

      else
        -- Def 0 values
        sCalEnable <= '0';
        sCalDump   <= '0';
        sCalAbort  <= '0';

        -- Memorizza CalibDone fino a quando non viene utilizzata da FSM
        if sCalibDone = '1' then
          sCalDoneLatched <= '1';
        end if;

        if sInjectStatus(2) = '1' or sInjectStatus(1) = '1' then
          sInjectRequested <= '0';
        end if;

        -- Con THR_Valid applico le soglie una sola volta
        if sThrApplyPending = '1' then
          sThrApplyPending <= '0';
        end if;

        -- Riabilita rising edge START
        if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
          sStartPrev <= '0';
        end if;

        case sRunState is

          -- Nessun comando attivo
          -- Un RUN_REQUEST nuovo campiona la configurazione e sceglie il percorso associato: calibrazione, dump, eventi oppure attesa dello STOP
          when RUN_IDLE =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              -- Pulizia conclusiva quando START e' basso.
              sRunMode          <= '0';
              sCommandHold      <= '0';
              sEventEnable      <= '0';
              sCalSave          <= '0';
              sCalOperationDump <= '0';
              sCalibrationRun   <= '0';
              sCalArmCounter    <= 0;
              sDrainIdleSeen    <= '0';
              sCalDoneLatched   <= '0';
              sInjectRequested  <= '0';

            elsif sStartPrev = '0' then
              -- risingEdge START: campiona tutti i campi del comando
              sStartPrev        <= '1';
              sDaqMode          <= sRegArray(rGOTO_STATE)(cDAQ_MODE_MSB downto cDAQ_MODE_LSB);
              sEventEnable      <= sRegArray(rGOTO_STATE)(cEVENT_ENABLE_BIT);
              sCalSave          <= sRegArray(rGOTO_STATE)(cSAVE_CALIB_BIT);
              sRunMode          <= '1';
              sCalArmCounter    <= 0;
              sDrainIdleSeen    <= '0';
              sCalDoneLatched   <= '0';
              sInjectRequested  <= '0';

              -- Le soglie sono acquisite insieme al comando e applicate al clock successivo
              if sRegArray(rGOTO_STATE)(cTHR_VALID_BIT) = '1' then
                sLTH             <= sRegArray(rTHR_PARAM)(15 downto 0);
                sHTH             <= sRegArray(rTHR_PARAM)(31 downto 16);
                sThrApplyPending <= '1';
              end if;

              -- Priorità del comando:
              --   1. calibrazione nuova
              --   2. dump di una calibrazione valida
              --   3. acquisizione eventi
              --   4. nessuna operazione, attesa dello STOP
              if sRegArray(rGOTO_STATE)(cFORCE_CALIB_BIT) = '1' or (sRegArray(rGOTO_STATE)(cAUTO_CALIB_BIT) = '1' and sCalibValid = '0') then
                sCommandHold      <= '1';
                sCalEnable        <= '1';
                sCalOperationDump <= '0';
                sCalibrationRun   <= '1';
                sInjectRequested  <= sRegArray(rGOTO_STATE)(cINJECT_BIT);
                sRunState         <= RUN_CAL_ARM;

              elsif sCalibValid = '1' and sRegArray(rGOTO_STATE)(cSAVE_CALIB_BIT) = '1' then
                sCommandHold      <= '1';
                sCalDump          <= '1';
                sCalOperationDump <= '1';
                sCalibrationRun   <= '1';
                sRunState         <= RUN_CAL_ARM;

              elsif sRegArray(rGOTO_STATE)(cEVENT_ENABLE_BIT) = '1' then
                sCalOperationDump <= '0';
                sCalibrationRun   <= '0';

                if sRegArray(rGOTO_STATE)(cTHR_VALID_BIT) = '1' then
                  -- Attende la propagazione di K1 e K2 per clustering.
                  sCommandHold <= '1';
                  sRunState    <= RUN_EVENT_ARM;
                else
                  sCommandHold <= '0';
                  sRunState    <= RUN_EVENTS;
                end if;

              else
                sCommandHold    <= '1';
                sCalibrationRun <= '0';
                sRunState       <= RUN_WAIT_STOP;
              end if;

            else
              -- RUN_REQUEST è ancora alto, ma nessun nuovo comando può partire finchè non arriva uno STOP
              sRunMode        <= '0';
              sCommandHold    <= '0';
              sCalibrationRun <= '0';
              sDrainIdleSeen  <= '0';
            end if;

          -- Attesa fissa dopo l'applicazione delle soglie e prima di
          -- accettare il primo trigger evento. IN LW servono gli ARM_CYCLE per applicare le soglie.
          -- TODO: Rimuovere questi ARM CYCLE e rendere l'applicazione istantanea
          when RUN_EVENT_ARM =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              -- Il lavoro gia' accettato viene drenato prima di tornare IDLE.
              sRunMode       <= '1';
              sCommandHold   <= '1';
              sCalArmCounter <= 0;
              sDrainIdleSeen <= '0';
              sRunState      <= RUN_STOP_DRAIN;
            else
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '0';
              sDrainIdleSeen  <= '0';

              if sCalArmCounter = cCAL_REQUEST_ARM_CYCLES-1 then
                sCommandHold   <= '0';
                sCalArmCounter <= 0;
                sRunState      <= RUN_EVENTS;
              else
                sCalArmCounter <= sCalArmCounter + 1;
              end if;
            end if;

          -- Acquisizione eventi: i trigger restano abilitati fino a quando non arriva STOP.
          when RUN_EVENTS =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode       <= '1';
              sCommandHold   <= '1';
              sCalArmCounter <= 0;
              sDrainIdleSeen <= '0';
              sRunState      <= RUN_STOP_DRAIN;
            else
              sRunMode        <= '1';
              sCommandHold    <= '0';
              sCalibrationRun <= '0';
              sDrainIdleSeen  <= '0';
            end if;

          -- Preparazione della calibrazione
          -- Per una calibrazione nuova CAL_ENABLE resta alto fino a READY
          -- per un dump viene rispettata soltanto l'attesa fissa per applicazione delle thr.
          when RUN_CAL_ARM =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '1';
              sDrainIdleSeen  <= '0';

              if sCalOperationDump = '1' then
                -- Il dump può essere già in corso e deve fermarsi su DONE
                sRunState <= RUN_STOP_CAL;
              else
                -- Nessun trigger è stato ancora accettato: abort immediato
                sCalAbort       <= '1';
                sCalDoneLatched <= '0';
                sRunState       <= RUN_STOP_DRAIN;
              end if;

            else
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '1';

              if sCalOperationDump = '1' then
                if sCalArmCounter = cCAL_REQUEST_ARM_CYCLES-1 then
                  sCalArmCounter <= 0;
                  sRunState      <= RUN_CALIBRATION;
                else
                  sCalArmCounter <= sCalArmCounter + 1;
                end if;
              else
                sCalEnable <= '1';

                if sCalibTrigReady = '1' and
                   (sInjectRequested = '0' or sInjectStatus(3) = '1') then
                  sCalEnable     <= '0';
                  sCommandHold   <= '0';
                  sCalArmCounter <= 0;
                  sRunState      <= RUN_CALIBRATION;
                end if;
              end if;
            end if;

          -- Calibrazione o dump in corso
          when RUN_CALIBRATION =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '1';
              sDrainIdleSeen  <= '0';

              if sCalibDone = '1' then
                -- DONE ha priorita
                sCalDoneLatched <= '0';
                sRunState       <= RUN_STOP_DRAIN;
              else
                -- Attende un confine sicuro prima di interrompere
                sRunState <= RUN_STOP_CAL;
              end if;

            else
              sRunMode        <= '1';
              sCommandHold    <= sCalOperationDump;
              sCalibrationRun <= '1';

              if sCalibDone = '1' then
                sCommandHold    <= '1';
                sCalDoneLatched <= '0';
                sDrainIdleSeen  <= '0';
                sRunState       <= RUN_CAL_DRAIN;
              end if;
            end if;

          -- La calibrazione è terminata normalmente. detector e TDAQ devono
          -- risultare entrambi idle per due clock consecutivi
          when RUN_CAL_DRAIN =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode       <= '1';
              sCommandHold   <= '1';
              sCalArmCounter <= 0;
              sDrainIdleSeen <= '0';
              sRunState      <= RUN_STOP_DRAIN;
            else
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '1';

              if sDetectorPipelineIdle = '1' and sTdaqDataIdle = '1' then
                if sDrainIdleSeen = '1' then
                  sDrainIdleSeen    <= '0';
                  sCalibrationRun   <= '0';
                  sCalOperationDump <= '0';
                  sCalSave          <= '0';

                  if sEventEnable = '1' then
                    sCommandHold <= '0';
                    sRunState    <= RUN_EVENTS;
                  else
                    sCommandHold <= '1';
                    sRunState    <= RUN_WAIT_STOP;
                  end if;
                else
                  sDrainIdleSeen <= '1';
                end if;
              else
                sDrainIdleSeen <= '0';
              end if;
            end if;

          -- Il comando non richiede altri trigger e resta attivo fino a STOP
          when RUN_WAIT_STOP =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode       <= '1';
              sCommandHold   <= '1';
              sCalArmCounter <= 0;
              sDrainIdleSeen <= '0';
              sRunState      <= RUN_STOP_DRAIN;
            else
              sRunMode        <= '1';
              sCommandHold    <= '1';
              sCalibrationRun <= '0';
              sDrainIdleSeen  <= '0';
            end if;

          -- STOP durante calibrazione/dump: attende DONE oppure un intervallo
          -- tra due trigger in cui l'abort non lascia dati parziali
          when RUN_STOP_CAL =>
            sRunMode        <= '1';
            sCommandHold    <= '1';
            sCalibrationRun <= '1';
            sDrainIdleSeen  <= '0';

            if sCalibDone = '1' or sCalDoneLatched = '1' then
              sCalDoneLatched <= '0';
              sRunState       <= RUN_STOP_DRAIN;
            elsif sCalOperationDump = '0' and sCalibTrigReady = '1' then
              sCalAbort       <= '1';
              sCalDoneLatched <= '0';
              sRunState       <= RUN_STOP_DRAIN;
            end if;

          -- STOP finale: conserva i metadati, blocca nuovi trigger e richiede
          -- due campioni idle consecutivi prima di tornare a RUN_IDLE
          when RUN_STOP_DRAIN =>
            sRunMode     <= '1';
            sCommandHold <= '1';

            if sDetectorPipelineIdle = '1' and sTdaqDataIdle = '1' then
              if sDrainIdleSeen = '1' then
                sRunMode          <= '0';
                sCommandHold      <= '0';
                sEventEnable      <= '0';
                sCalSave          <= '0';
                sCalOperationDump <= '0';
                sCalibrationRun   <= '0';
                sCalArmCounter    <= 0;
                sDrainIdleSeen    <= '0';
                sCalDoneLatched   <= '0';
                sInjectRequested  <= '0';
                sRunState         <= RUN_IDLE;
              else
                sDrainIdleSeen <= '1';
              end if;
            else
              sDrainIdleSeen <= '0';
            end if;

          -- Recupero da un eventuale valore di stato non valido
          when others =>
            if sRegArray(rGOTO_STATE)(cRUN_REQUEST_BIT) = '0' then
              sRunMode       <= '1';
              sCommandHold   <= '1';
              sCalArmCounter <= 0;
              sDrainIdleSeen <= '0';
              sRunState      <= RUN_STOP_DRAIN;
            else
              sRunMode        <= '0';
              sCommandHold    <= '0';
              sCalibrationRun <= '0';
              sDrainIdleSeen  <= '0';
              sCalDoneLatched <= '0';
              sRunState       <= RUN_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process REGISTER_COMMAND_PROC;

  --!@brief Detector interface. **Reset shall be longer than 2 clock cycles**
  --!@todo Connect error, compl flags
  MsdInterface : DetectorInterface
    port map (
      iCLK            => sClk,
      iRST            => sDetIntfRst, --See the instance description
      iEN             => sDetIntfEn,
      iTRIG           => sMainTrig,
      oCNT            => sDetIntfCntOut,  --Temporary
      iMSD_CONFIG     => sDetIntfCfg,
      oFE0            => sFeA,
      oADC0           => sAdcA,
      oFE1            => sFeB,
      oADC1           => sAdcB,
      iMULTI_ADC      => sMultiAdcSynch,
      oFASTDATA_DATA  => sDetIntfQ,
      oFASTDATA_WE    => sDetIntfWe,
      iFASTDATA_AFULL => sDetIntfAfull,
      oPACKET_VALID   => sPacketValid,
      oPAYLOAD_WORDS  => sPayloadWords,
      oTRIG_TYPE      => sPacketTrigType,
      iTHR_VALID      => sThrValid,
      iLTH            => sLTH,
      iHTH            => sHTH,
      iDAQ_MODE       => sDetectorDaqMode,
      iCAL_ENABLE     => sCalEnable,
      iCAL_DUMP       => sCalDump,
      iCAL_SAVE       => sCalSave,
      iCAL_ABORT      => sCalAbort,
      iEVT_ENABLE     => sEventEnable,
      iINJECT_ENABLE  => sInjectRequested,
      iINJECT_DATA    => sInjectData,
      iINJECT_WE      => sInjectWe,
      iINJECT_CLEAR   => sInjectClear,
      iINJECT_END     => sInjectEnd,
      oINJECT_STATUS  => sInjectStatus,
      oCALIB_VALID    => sCalibValid,
      oCALIB_DONE     => sCalibDone,
      oCALIB_TRIG_READY => sCalibTrigReady,
      oPIPELINE_IDLE  => sDetectorPipelineIdle,
      oLED  => LED(3 downto 0)
      );

  biasStartSynch : altera_std_synchronizer
    generic map (
      depth => 3
      )
    port map (
      clk     => sClk,
      reset_n => hps_fpga_reset_n_synch,
      din     => fpga_debounced_buttons_n(0),
      dout    => sBiasButtonSynch
      );

  --!@brief Generate the pulse for starting bias voltage.
  biasStartEdge : altera_edge_detector
    generic map(
      PULSE_EXT             => 5,
      EDGE_TYPE             => 1,
      IGNORE_RST_WHILE_BUSY => 0
      )
    port map (
      clk       => sClk,
      rst_n     => hps_fpga_reset_n_synch,
      signal_in => sBiasButtonSynch,
      pulse_out => sbiasStart
      );

  HV_REQUEST_EDGE_PROC : process(sClk)
  begin
    if rising_edge(sClk) then
      if hps_fpga_reset_n_synch = '0' or sDetIntfRst = '1' then
        sHvRqtPrev <= (others => '0');
      else
        sHvRqtPrev <= sRegArray(rHV_PARAM)(31) & sRegArray(rHV_PARAM)(15);
      end if;
    end if;
  end process HV_REQUEST_EDGE_PROC;

  sHvRqt(1) <= (sRegArray(rHV_PARAM)(31) and not sHvRqtPrev(1)) or sbiasStart;
  sHvValue1 <= sRegArray(rHV_PARAM)(25 downto 16);
  sHvMon(31) <= sHvAck(1);
  sHvMon(30) <= sHvErr(1);
  HV_1_DAC : LT1663Intf
    port map(
      iCLK  => sClk,
      iRST  => sDetIntfRst,
      iRQT  => sHvRqt(1),
      oACK  => sHvAck(1),
      oERR  => sHvErr(1),
      iHV   => sHvValue1,
      ioSDA => ioVSET_SDA(1),
      oSCL  => oVSET_SCL(1)
    );
  
  sHvRqt(0) <= (sRegArray(rHV_PARAM)(15) and not sHvRqtPrev(0)) or sbiasStart;
  sHvValue0 <= sRegArray(rHV_PARAM)(9 downto 0);
  sHvMon(15) <= sHvAck(0);
  sHvMon(14) <= sHvErr(0);
  sHvMon(13 downto 12) <= (others => '0');
  HV_0_DAC : LT1663Intf
    port map(
      iCLK  => sClk,
      iRST  => sDetIntfRst,
      iRQT  => sHvRqt(0),
      oACK  => sHvAck(0),
      oERR  => sHvErr(0),
      iHV   => sHvValue0,
      ioSDA => ioVSET_SDA(0),
      oSCL  => oVSET_SCL(0)
    );
  
  sHvMon(27 downto 16) <= sBiasCurrent(1);
  sHvMon(11 downto 0) <= sBiasCurrent(0);
  biasCurrentMonitor : biasCurrLTC2312
   generic map(
      pDEPTH => cLTC2312_DEPTH,
      pADCS => cLTC2312_ADCS
  )
   port map(
      iCLK => sClk,
      iRST => sDetIntfRst,
      oBUSY => sHvMon(29),
      oCOMPL => sHvMon(28),
      iEN => sRegArray(rHV_PARAM)(30),
      iSTART => sBiasCurrentStart,
      oCONV => sBiasCurrentConv,
      oSCK => sBiasCurrentSck,
      iSDO => sBiasCurrentSdo,
      oQ_CONV => sBiasCurrent,
      oWR => sBiasCurrWr
  );

  biasCurrentStarter : clock_divider_2
   generic map(
      pPOLARITY => '1',
      pWIDTH => 32
  )
   port map(
      iCLK => sClk,
      iRST => sDetIntfRst,
      iEN => sRegArray(rHV_PARAM)(30),
      oCLK_OUT_RISING => sBiasCurrentStart,
      iFREQ_DIV => x"02faf080", --2faf080: 1sec@50MHz
      iDUTY_CYCLE => x"017d7840" --17d7840: 50%@50MHz
  );

  -- GPIO connections ----------------------------------------------------------
  -- HEF-0
  oVA_DRESET(0)       <= sFeA.DRst;
  oVA_HOLDb(0)        <= sFeA.Hold;
  oVA_SHIFT_IN(0)     <= sFeA.ShiftIn;
  oVA_CLKb(0)         <= sFeA.Clk;
  oADC_CONV(0)        <= sAdcA.Cs;
  oADC_SCK(0)         <= sAdcA.Sclk;
  sMultiAdc(0).SData  <= iADC_DATA_1(0);
  sMultiAdc(1).SData  <= iADC_DATA_2(0);
  sMultiAdc(2).SData  <= iADC_DATA_3(0);
  sMultiAdc(3).SData  <= iADC_DATA_4(0);
  sMultiAdc(4).SData  <= iADC_DATA_5(0);
  sMultiAdc(5).SData  <= iADC_DATA_6(0);
  sMultiAdc(6).SData  <= iADC_DATA_7(0);
  oIMON_CONV(0) <= sBiasCurrentConv;
  oIMON_SCK(0)  <= sBiasCurrentSck;
  sBiasCurrentSdo(0) <= iIMON_SDO(0);
  
  -- HEF-1
  oVA_DRESET(1)       <= sFeB.DRst;
  oVA_HOLDb(1)        <= sFeB.Hold;
  oVA_SHIFT_IN(1)     <= sFeB.ShiftIn;
  oVA_CLKb(1)         <= sFeB.Clk;
  oADC_CONV(1)        <= sAdcB.Cs;
  oADC_SCK(1)         <= sAdcB.Sclk;
  sMultiAdc(7).SData  <= iADC_DATA_1(1);
  sMultiAdc(8).SData  <= iADC_DATA_2(1);
  sMultiAdc(9).SData  <= iADC_DATA_3(1);
  sMultiAdc(10).SData <= iADC_DATA_4(1);
  sMultiAdc(11).SData <= iADC_DATA_5(1);
  sMultiAdc(12).SData <= iADC_DATA_6(1);
  sMultiAdc(13).SData <= iADC_DATA_7(1);
  oIMON_CONV(1) <= sBiasCurrentConv;
  oIMON_SCK(1)  <= sBiasCurrentSck;
  sBiasCurrentSdo(1) <= iIMON_SDO(1);

  --- I/O synchronization and buffering ----------------------------------------
  oCTX_GND <= (others => '0');
  ioCTX_OD <= (others => 'Z');
  
  BCO_CLK_SYNCH : sync_edge
    generic map (
      pSTAGES => 3
      )
    port map (
      iCLK    => sClk,
      iRST    => '0',
      iD      => iCTX_TIME_CLK,
      oEDGE_R => sBcoClkSynch
      );

  BCO_RST_SYNCH : sync_edge
    generic map (
      pSTAGES => 3
      )
    port map (
      iCLK    => sClk,
      iRST    => '0',
      iD      => iCTX_TIME_RST,
      oQ      => sBcoRstReplica,
      oEDGE_R => sBcoRstSynch
      );
  
  EXT_TRIG_RE : sync_edge
    generic map (
      pSTAGES => 3
      )
    port map (
      iCLK    => sClk,
      iRST    => '0',
      iD      => iCTX_EXT_TRIG,
      oEDGE_R => sExtTrigSynch
      );

  sMultiAdcSynch <= sMultiAdc;
  IOFFD : process(sClk)
  begin
    if rising_edge(sClk) then
      oCTX_BUSY <= sMainBusy;
      oCTX_TRIG <= sMainTrig;
    --!@todo synchronize also the ADC incoming data and the CD and SCLK ret
    end if;
  end process IOFFD;

end architecture;
