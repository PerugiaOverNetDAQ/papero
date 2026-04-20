--!@file LT1663Intf.vhd
--!@brief LT1663 2-Wire Interface
--!@author Mattia Barbanera, mattia.barbanera@pg.infn.it

library ieee;
use ieee.std_logic_1164.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
--use ieee.std_logic_arith.all;

--!@copydoc LT1663Intf.vhd
entity LT1663Intf is port (
  iCLK  : in    std_logic;
  iRST  : in    std_logic;
  -- Main Control Interface
  iRQT  : in    std_logic; --!Start transaction request
  oACK  : out   std_logic; --!Acknowledgment of transaction completion
  oERR  : out   std_logic; --!Error signal for transaction failure
  -- HV setting input
  iHV   : in    std_logic_vector(9 downto 0); --!10-bit input for DAC voltage setting
  -- 2-Wire Interface; should be high when not in use (datasheet, pag. 7)
  ioSDA : inout std_logic; --!Bidirectional data line
  oSCL  : out   std_logic  --!Clock line
  );
end LT1663Intf;

--!@copydoc LT1663Intf.vhd
architecture LT1663_arch of LT1663Intf is

  type t1663State is (IDLE, START, SHIFT, ACK, STOP);
  signal s1663State : t1663State;         --FSM Current state

  -- Signals for data shifting, clock division, counters, and acknowledgment
  signal sSro  : std_logic_vector(7 downto 0);  --Data shift register
  signal sPDiv : integer range 0 to 4;  --Clock divider for timing
  signal sCnt  : integer range 0 to 7;  --Bit counter for 8-bit data
  signal sBCnt : integer range 0 to 3;  --Byte counter for multi-byte transfers

  signal sCommAck : std_logic;

  -- Request and control signals
  signal sRqtS : std_logic;             --Start request signal
  signal sRqt1 : std_logic;             --Intermediate request signal
  signal sRqt2 : std_logic;             --Delayed request signal
  signal sDa   : std_logic;             --Data line control
  signal sCl   : std_logic;             --Clock line control

  signal sSroMux : std_logic_vector(7 downto 0);  --Multiplexer for shift register data

begin
  --!Handle requests and manage the start condition for LT1663 communication
  REQ_HANDLING : process (iCLK, iRQT)
  begin
    if iRQT = '1' then
      sRqt1 <= '1';    --On external request set intermediate request
    elsif falling_edge(iCLK) then
      if sRqt2 = '1' then
        sRqt1 <= '0';  --Clear intermediate request after it has been registered
      end if;
    end if;
  end process REQ_HANDLING;

  ioSDA <= '0' when sDa = '0' else 'Z';

  --sBCnt=0 is the DAC command byte X X X X X BG SD SY
  --  2: BG Band-Gap reference: '0' power supply, '1' internal
  --  1: SD Power Down: '0' OFF, '1' ON
  --  0: SY Update on '0' Stop condition, '1' Ack
  sSroMux <= "00000100" when sBCnt = 0 else
             iHV(7 downto 0) when sBCnt = 1 else
             "000000" & iHV(9 downto 8);

  oACK <= '1' when s1663State = STOP else '0';

  oERR <= sCommAck;
  oSCL <= sCl;

  LT1663_INTF_PROC : process (iCLK, iRST)
  begin
    if iRST = '1' then
      sPDiv     <= 0;
      sRqtS <= '0';
      sDa   <= '1';
      sCl   <= '1';
      sCnt  <= 0;
      sBCnt <= 0;
      sRqt2 <= '0';
      sSro    <= (others => '0');
      sCommAck <= '0';
      s1663State <= IDLE;

    elsif rising_edge(iCLK) then
      -- Update delayed request signal (will reset it automatically after one clock cycle)
      sRqt2 <= sRqt1;

      -- Handle start request: high if external request; low after IDLE
      -- FIXME: queue? Request when in START?
      if sRqt2 = '1' then
        sRqtS <= '1';
      end if;
      if s1663State = START then
        sRqtS <= '0';
      end if;

      -- 
      sPDiv <= sPDiv + 1;
      if sPDiv = 4 then
        sPDiv <= 0;
      end if;

      -- Clock line control, based on state and clock divider
      if sPDiv = 1 then
        sCl <= '1';
      end if;
      if (s1663State = START or s1663State = SHIFT or s1663State = ACK) and sPDiv = 3 then
        sCl <= '0';
      end if;

      -- Data line control, based on clock divider and state
      if sPDiv = 2 then
        --Start condition
        if s1663State = START then
          sDa <= '0';
        end if;
        --Stop condition
        if s1663State = STOP then
          sDa <= '1';
        end if;
      end if;

      --
      if sPDiv = 4 then
        if s1663State = STOP then
          sDa <= '0';
        end if;
        if s1663State = ACK then
          sDa <= '1';
        end if;
        if s1663State = SHIFT then
          sDa <= sSro(7);
        end if;
      end if;

      -- Shift register handling and acknowledgment processing
      if sPDiv = 3 then
        -- Start condition: load the shift register with the 2-wire address
        if s1663State = START then
          sSro <= "01000000"; --[7:1] Default address; [0] Write. 0x40
        end if;
        -- Shift data bits out on the SDA line
        if s1663State = SHIFT then
          sCnt <= sCnt + 1;
          sSro <= sSro(6 downto 0) & '1';
        end if;
        -- Handle acknowledgment from the slave device
        if s1663State = ACK then
          sCommAck <= ioSDA;
          sBCnt   <= sBCnt + 1;
          sSro    <= sSroMux;
        end if;
        -- Reset control signals and counters when returning to IDLE state
        if s1663State = IDLE then
          sDa   <= '1';
          sCl   <= '1';
          sCnt  <= 0;
          sBCnt <= 0;
        end if;
      end if;

      -- State transitions
      if sPDiv = 3 then
        case s1663State is
          when IDLE =>
            if sRqtS = '1' then
              s1663State <= START;
            end if;
          when START =>
            s1663State <= SHIFT;
          when SHIFT =>
            if sCnt = 7 then -- 8-bit words + ACK
              s1663State <= ACK;
            end if;
          when ACK =>
            s1663State <= SHIFT; -- Send all bytes before stopping
            if sBCnt = 3 or ioSDA = '1' then
              s1663State <= STOP;
            end if;
          when STOP =>
            s1663State <= IDLE;
          when others => s1663State <= IDLE;
        end case;
      end if;
    end if; --iCLK
  end process LT1663_INTF_PROC;

end LT1663_arch;
