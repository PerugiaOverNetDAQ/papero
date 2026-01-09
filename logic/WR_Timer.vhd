--!@file WR_Timer.vhd
--!@brief Generatore di impulsi per estrarre un payload dalla FIFO
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;
use work.paperoPackage.all;
use work.basic_package.all;

--!@copydoc WR_Timer.vhd
entity WR_Timer is
  port(
    WRT_CLK_in              : in  std_logic;  -- Segnale di clock.
    WRT_RST_in              : in  std_logic;  -- Segnale di reset.
    WRT_START_in            : in  std_logic;  -- Segnale di "payload_enable" prodotto dal Config_Receiver. Vale '1' solo se PS=ACQUISITION.
    WRT_STANDBY_in          : in  std_logic;  -- Segnale di Wait_Request in uscita dalla FIFO. Se Wait_Request=1 --> la FIFO è vuota.
    WRT_STOP_COUNT_VALUE_in : in  std_logic_vector(31 downto 0);  -- Lunghezza del payload + 5.
    WRT_out                 : out std_logic;  -- Impulsi di Read_Enable per acquisire il payload dalla FIFO. Se Read_Enable=1 --> la FIFO estrarrà il primo dato che ha ricevuto in ingresso.
    WRT_END_COUNT_out       : out std_logic  -- Fine della trasmissione degli impulsi di Read_Enable per acquisire il payload.
    );
end WR_Timer;

--!@copydoc WR_Timer.vhd
architecture Behavior of WR_Timer is
  signal reset            : std_logic;  -- Segnale interno di reset
  signal start            : std_logic;  -- Segnale interno "payload_enable". E' "alto" solo se ci troviamo nello stato di "ACQUISITION" della macchina a stati
  signal standby          : std_logic;  -- Segnale interno di "Wait_Request" della FIFO
  signal stop_count_value : std_logic_vector(31 downto 0);  -- Lunghezza del payload acquisita dal WR_Timer all'inizio di ogni sessione dei burst di Read_Enable
  signal output           : std_logic;  -- Segnale interno che trasporata gli impulsi di "Read_Enable"
  signal timer_on         : std_logic;  -- Stato del timer. timer_on=1 --> acceso
  signal start_R          : std_logic;  -- Impulso sul fronte di salita del "payload_enable". Ci indica che siamo appena entrati nello stato di "ACQUISITION"
  signal general_counter  : std_logic_vector(31 downto 0);  -- Contatore del numero di impulsi inviati in uscita
  signal pulse_counter    : std_logic_vector(31 downto 0);  -- Contatore della parità degli impulsi. Se pulse_counter=1-->siamo su un impulso dispari

begin
  reset   <= WRT_RST_in;  -- Assegnazione della porta di WRT_RST_in ad un segnale interno
  start   <= WRT_START_in;  -- Assegnazione della porta di WRT_START_in ad un segnale interno
  standby <= WRT_STANDBY_in;  -- Assegnazione della porta di WRT_STANDBY_in ad un segnale interno

  -- Instanziamento dello User Edge Detector
  rise_edge_implementation : edge_detector_2
    generic map(
      channels => 1,
      R_vs_F   => '0'
      )
    port map(
      iCLK     => WRT_CLK_in,
      iRST     => reset,
      iD(0)    => start,
      oEDGE(0) => start_R
      );


  -- Accensione/spegnimento del Timer
  Timer_On_Off_proc : process (WRT_CLK_in)
  begin
    if rising_edge(WRT_CLK_in) then
      if ((reset = '1') or (start = '0')) then
        timer_on          <= '0';  -- Se siamo in "RESET" o non siamo in "ACQUISITION", spegni il timer
        stop_count_value  <= (others => '0');
        WRT_END_COUNT_out <= '0';
      elsif (start_R = '1') then
        timer_on          <= '1';  -- Se siamo appena entrati in "ACQUISITION", accendi il timer
        stop_count_value  <= WRT_STOP_COUNT_VALUE_in - 5;
        WRT_END_COUNT_out <= '0';
      elsif (general_counter + 1 > stop_count_value) then
        timer_on          <= '0';
        WRT_END_COUNT_out <= '1';  -- Se il timer ha raggiunto il suo valore massimo, spegnilo
      end if;
    end if;
  end process;

  counter_PWM_proc : process (WRT_CLK_in)
  begin
    if rising_edge(WRT_CLK_in) then
      if ((reset = '1') or (start_R = '1')) then
        pulse_counter <= (others => '0');  -- Se siamo in "RESET" o siamo appena entrati in "ACQUISITION", azzera il contatore della disparità
      elsif ((timer_on = '1') and (standby = '0')) then
        if (pulse_counter < 1) then  -- Se il timer è acceso, il wait_request della FIFO è basso e l'ultimo Read_Enable era pari, metti a '1' il contatore della disparità
          pulse_counter <= pulse_counter + 1;
        else                            -- In tutti gli altri casi, azzeralo
          pulse_counter <= (others => '0');
        end if;
      else
        pulse_counter <= (others => '0');
      end if;
    end if;
  end process;

  output_proc : process (WRT_CLK_in)
  begin
    if rising_edge(WRT_CLK_in) then
      if ((reset = '1') or (start_R = '1')) then
        output          <= '0';  -- Se siamo in "RESET" o siamo appena entrati in "ACQUISITION", azzera il contatore degli impulsi di Read_Enable e porta l'uscita ad un valore basso
        general_counter <= (others => '0');
      elsif ((timer_on = '1') and (standby = '0')) then
        if (pulse_counter < 1) then  -- Se il timer è acceso, il wait_request della FIFO è basso e l'ultimo Read_Enable era pari, incrementa il contatore della disparità degli impulsi di Read_Enable e metti l'uscita alta
          output          <= '1';
          general_counter <= general_counter + 1;
        else
          output <= '0';  -- In tutti gli altri casi, azzera il contatore degli impulsi di Read_Enable e porta l'uscita ad un valore basso
        end if;
      else
        output <= '0';
      end if;
    end if;
  end process;


  -- Data Flow per il controllo dell'uscita (impulsi di Read_Enable da inviare alla FIFO)
  WRT_out <= output and (not reset) and start;  -- Segui il segnale "output", ma siamo in "RESET" o siamo appena usciti dallo stato di "ACQUISITION", porta immediatamente l'uscita a '0'


end Behavior;
