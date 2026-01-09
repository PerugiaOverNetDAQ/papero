--!@file Config_Receiver.vhd
--!@brief Decode the input commands and write them to the array registers.
--!@details
--!
--!Read the incoming packets containing the instructions and write them to the
--! register array. The format is specified in PAPERO_formats.xlsx: \n
--!
--! | Abbr  | Description | Default |
--! |-------|-------------|---------|
--! |SoP | Start-of-Packet | x"AA55CA5A" |
--! |Len | Length | Number of 32-bit payload words + 5 |
--! |Ver | Firmware Version | - |
--! |Hdr | Fixed hader | x"4EADE500" |
--! |    | [31:0]  Register Content | - |
--! |    | [31:24] parity bits, [23:16] Instruction, [15:0] Register Address | - |
--! |    | ................ | - |
--! |Trl | Trailer | x"BADC0FEE" |
--! |CRC | CRC-32 | - |
--!
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

use work.paperoPackage.all;
use work.basic_package.all;

--!@copydoc Config_Receiver.vhd
entity Config_Receiver is
  port(
    CR_CLK_in               : in  std_logic;  -- Segnale di clock.
    CR_RST_in               : in  std_logic;  -- Segnale di reset.
    CR_FIFO_WAIT_REQUEST_in : in  std_logic;  -- Segnale di Wait_Request in uscita dalla FIFO. Se Wait_Request=1 --> la FIFO è vuota.
    CR_DATA_in              : in  std_logic_vector(31 downto 0);  -- Dati in uscita dalla FIFO.
    CR_FWV_in               : in  std_logic_vector(31 downto 0);  -- Firmware Version (Generato da Hog come SHA dell'ultimo commit).
    CR_FIFO_READ_EN_out     : out std_logic;  -- Segnale di Read_Enable in ingresso alla FIFO. Se Read_Enable=1 --> la FIFO estrarrà il primo dato che ha ricevuto in ingresso.
    CR_DATA_out             : out std_logic_vector(31 downto 0);  -- Dati in uscita dal ricevitore.
    CR_ADDRESS_out          : out std_logic_vector(15 downto 0);  -- Indirizzo del registro in cui memorizzare il valore di "CR_DATA_out".
    CR_DATA_VALID_out       : out std_logic;  -- Segnale che attesta la validità dei dati in uscita dal ricevitore. Se Data_Valid=1 --> il valore di "CR_DATA_out" è consistente e può essere memorizzato.
    CR_WARNING_out          : out std_logic_vector(2 downto 0)  -- Segnale di avviso dei malfunzionamenti del Config_Receiver. "000"-->ok, "001"-->errore sui bit di parità, "010"-->errore nella struttura del pacchetto (word missed), "100"-->errore generico (ad esempio se la macchina finisce in uno stato non precisato oppure se la firmware version è errata).
    );
end Config_Receiver;

--!@copydoc Config_Receiver.vhd
architecture Behavior of Config_Receiver is
  type STATUS is (RESET, SYNCH, SEARCH_SOP, SEARCH_LEN, SEARCH_FWV, SEARCH_HEADER, ACQUISITION, SEARCH_COFEE, SEARCH_CRC, REBOUND, warning);  -- Il Config_Receiver è una macchina a stati costituita da 11 stati.
  signal ps, ns : STATUS;               -- PS=Present Status, NS=Next Status.

-- Set di costanti utili per la risoluzione del pacchetto ricevuto.
  constant start_of_packet : std_logic_vector(31 downto 0) := x"AA55CA5A";  -- Start of packet.
  constant header          : std_logic_vector(31 downto 0) := x"4EADE500";  -- Header word.
  constant trailer         : std_logic_vector(31 downto 0) := x"BADC0FEE";  -- Bad Cofee.
  constant trailer_crc     : std_logic_vector(31 downto 0) := x"FFFFFFFF";  -- Parola di default usata al posto del CRC.
  constant gnd             : std_logic                     := '0';  -- Singola linea a massa.
  constant zero            : std_logic_vector(31 downto 0) := (others => '0');  -- 32 linee a massa.

-- Set di segnali che si attivano al verificarsi di un dato evento.
  signal fifo_wait_request    : std_logic;  -- La FIFO è vuota.
  signal fifo_wait_request_d  : std_logic;  -- fifo_wait_request ritardato di 1 ciclo di clock.
  signal fifo_wait_request_HH : std_logic;  -- fifo_wait_request tenuta "alta" per un ciclo di clock aggiuntivo.
  signal synch_pulse          : std_logic;  -- Lo stato della FIFO è passato da vuoto a non vuoto.
  signal synch_pulse_HH       : std_logic;  -- Lo stato della FIFO è passato da vuoto a non vuoto (sulla base di Wait_Request_HH).
  signal fwv_missed           : std_logic;  -- La word di FirmWare Version non è corretta.
  signal header_missed        : std_logic;  -- La word di Header non è corretta.
  signal payload_done         : std_logic;  -- Il payload è stato acquisito correttamente.
  signal fast_payload_done    : std_logic;  -- Il payload è stato acquisito correttamente. Passa fin da subito nello stato successivo.
  signal false_payload        : std_logic;  -- Si è verificato un errore sui bit di parità del payload.
  signal cofee_missed         : std_logic;  -- La word di trailer non è corretta.
  signal crc_missed           : std_logic;  -- La word di crc non è corretta.

-- Set di segnali il cui valore indica la presenza in un preciso stato della macchina a stati.
  signal internal_reset      : std_logic;  -- '1' solo se PS=RESET
  signal synch_enable        : std_logic;  -- '1' solo se PS=SYNCH
  signal start_packet_enable : std_logic;  -- '1' solo se PS=SEARCH_SOP
  signal length_enable       : std_logic;  -- '1' solo se PS=SEARCH_LENGTH
  signal fwv_enable          : std_logic;  -- '1' solo se PS=SEARCH_FWV
  signal header_enable       : std_logic;  -- '1' solo se PS=SEARCH_HEADER
  signal payload_enable      : std_logic;  -- '1' solo se PS=ACQUISITION
  signal cofee_enable        : std_logic;  -- '1' solo se PS=SEARCH_COFEE
  signal crc_enable          : std_logic;  -- '1' solo se PS=SEARCH_CRC
  signal rebound_enable      : std_logic;  -- '1' solo se PS=REBOUND
  signal warning_enable      : std_logic;  -- '1' solo se PS=WARNING

-- Set di impulsi generati sul fronte di salita dai rispettivi segnali di "enable".
  signal internal_reset_R      : std_logic;
  signal synch_enable_R        : std_logic;
  signal start_packet_enable_R : std_logic;
  signal length_enable_R       : std_logic;
  signal fwv_enable_R          : std_logic;
  signal fwv_missed_R          : std_logic;
  signal header_enable_R       : std_logic;
  signal payload_enable_R      : std_logic;
  signal payload_enable_WRT    : std_logic;
  signal cofee_enable_R        : std_logic;
  signal crc_enable_R          : std_logic;
  signal rebound_enable_R      : std_logic;
  signal warning_enable_R      : std_logic;
  signal end_count_WRTimer_R   : std_logic;

-- Set di segnali utili per il Signal Processing.
  signal length_packet     : std_logic_vector(31 downto 0);  -- Lunghezza del payload + 5.
  signal data              : std_logic_vector(31 downto 0);  -- Dati contenuti nel payload.
  signal address           : std_logic_vector(15 downto 0);  -- Indirizzo contenuto nel payload.
  signal data_RX           : std_logic_vector(31 downto 0);  -- Dati ricevuti la cui correttezza è da verificare.
  signal address_RX        : std_logic_vector(15 downto 0);  -- Indirizzo ricevuto la correttezza è da verificare.
  signal parity            : std_logic_vector(7 downto 0);  -- Bit di parità del pacchetto.
  signal estimated_parity  : std_logic_vector(7 downto 0);  -- Bit di parità stimati dal ricevitore.
  signal estimated_CRC32   : std_logic_vector(31 downto 0);  -- Codice a Ridondanza Ciclica stimato dal ricevitore.
  signal CRC32_on          : std_logic;  -- Abilitazione del modulo per il calcolo del codice a ridondanza ciclica.
  signal download_phase    : std_logic_vector(1 downto 0);  -- Fase di scaricamento del payload.
  signal end_count_WRTimer : std_logic;  -- Fine della trasmissione degli impulsi di Read_Enable per acquisire il payload.
  signal data_valid        : std_logic;  -- Consistenza del dato in uscita dal ricevitore.
  signal data_ready        : std_logic;  -- Dato pronto per essere trasferito in uscita dal ricevitore.

begin
  -- Assegnazione egnali interni al Config_Receiver
  fifo_wait_request <= CR_FIFO_WAIT_REQUEST_in;  -- Assegnazione della porta di Wait_Request ad un segnale interno.
  CRC32_on          <= fwv_enable_R or header_enable_R or (payload_enable_WRT and payload_enable);  -- Abilitazione del modulo CRC32 (SEARCH_FWV, SEARCH_HEADER, ACQUISITION)

  -- Instanziamento dello User Edge Detector per generare gli impulsi di Read_Enable che identificano una specifica transizione da uno stato all'altro della macchina.
  rise_edge_implementation : edge_detector_2
    generic map(channels => 14, R_vs_F => '0')
    port map(
      iCLK      => CR_CLK_in,
      iRST      => gnd,
      iD(0)     => internal_reset,
      iD(1)     => synch_enable,
      iD(2)     => start_packet_enable,
      iD(3)     => length_enable,
      iD(4)     => fwv_enable,
      iD(5)     => fwv_missed,
      iD(6)     => header_enable,
      iD(7)     => payload_enable,
      iD(8)     => cofee_enable,
      iD(9)     => crc_enable,
      iD(10)    => rebound_enable,
      iD(11)    => warning_enable,
      iD(12)    => data_ready,
      iD(13)    => end_count_WRTimer,
      oEDGE(0)  => internal_reset_R,
      oEDGE(1)  => synch_enable_R,
      oEDGE(2)  => start_packet_enable_R,
      oEDGE(3)  => length_enable_R,
      oEDGE(4)  => fwv_enable_R,
      oEDGE(5)  => fwv_missed_R,
      oEDGE(6)  => header_enable_R,
      oEDGE(7)  => payload_enable_R,
      oEDGE(8)  => cofee_enable_R,
      oEDGE(9)  => crc_enable_R,
      oEDGE(10) => rebound_enable_R,
      oEDGE(11) => warning_enable_R,
      oEDGE(12) => data_valid,
      oEDGE(13) => end_count_WRTimer_R
      );

  -- Instanziamento dello User Edge Detector per generare gli impulsi di "synch_pulse" per risincronizzare l'uscita della FIFO con l'ingresso del ricevitore quando la FIFO passa da vuota a non vuota.
  fall_edge_implementation : edge_detector_2
    generic map(channels => 2, R_vs_F => '1')
    port map(
      iCLK     => CR_CLK_in,
      iRST     => gnd,
      iD(0)    => fifo_wait_request,
      iD(1)    => fifo_wait_request_HH,
      oEDGE(0) => synch_pulse,
      oEDGE(1) => synch_pulse_HH  -- Questa synch_pulse segue il segnale di fifo_wait_request tenuto alto per un ciclo aggiuntivo.
      );

  -- Instanziamento dell'HighHold per evitare che il "Wait_Request" rimanga alto per un solo ciclo di clock (ma almeno 2), situazione potenzialmente dannosa per la macchina.
  Hold_Wait_Request : HighHold
    generic map(pCH => 1)
    port map(
      iCLK         => CR_CLK_in,
      iDATA(0)     => fifo_wait_request,
      oDEL_1(0) => fifo_wait_request_HH
      );

  -- Instanziamento del WR_Timer per generare gli impulsi di Read_Enable specifici per lo stato di "ACQUISITION".
  timer : WR_Timer
    port map (
      WRT_CLK_in              => CR_CLK_in,
      WRT_RST_in              => internal_reset,
      WRT_START_in            => payload_enable,
      WRT_STANDBY_in          => fifo_wait_request_HH,
      WRT_STOP_COUNT_VALUE_in => length_packet,
      WRT_out                 => payload_enable_WRT,
      WRT_END_COUNT_out       => end_count_WRTimer
      );

  -- Compute the CRC32 for packet content (except for SoP, Len, and EoP)
  Calcolo_CRC32 : CRC32
    generic map(
      pINITIAL_VAL => x"FFFFFFFF"
      )
    port map(
      iCLK    => CR_CLK_in,
      iRST    => internal_reset,
      iCRC_EN => CRC32_on,
      iDATA   => CR_DATA_in,
      oCRC    => estimated_CRC32
      );


  -- Next State Evaluation
  delta_proc : process (ps, fifo_wait_request, fifo_wait_request_HH, CR_DATA_in, payload_done, fast_payload_done, false_payload)
  begin
    case ps is
      when RESET =>  -- Sei in RESET. Se nella FIFO c'è qualcosa passa a SYNCH, altrimenti rimani qui.
        if (fifo_wait_request = '0') then
          ns <= SYNCH;
        else
          ns <= RESET;
        end if;
      when SYNCH =>  -- Sei in SYNCH. Passa immediatamente a SEARCH SOP. Grazie al passaggio in questo stato, il ricevitore vedrà recapitarsi i pacchetti con la giusta fase temporale.
        ns <= SEARCH_SOP;
      when SEARCH_SOP =>  -- Sei in SEARCH_SOP. Se lo start of packet ricevuto è corretto e nella FIFO c'è qualcosa, passa allo stato successivo, altrimenti vai in "REBOUND".
        if ((CR_DATA_in = start_of_packet) and (fifo_wait_request_HH = '0')) then
          ns <= SEARCH_LEN;
        elsif ((not(CR_DATA_in = start_of_packet)) and (fifo_wait_request_HH = '0')) then
          ns <= REBOUND;
        else
          ns <= SEARCH_SOP;
        end if;
      when SEARCH_LEN =>  -- Sei in SEARCH_LEN. Se nella FIFO c'è qualcosa, passa nello stato successivo, altrimenti rimani qui.
        if (fifo_wait_request_HH = '0') then
          ns <= SEARCH_FWV;
        else
          ns <= SEARCH_LEN;
        end if;
      when SEARCH_FWV =>  -- Sei in SEARCH_FWV. Se nella FIFO c'è qualcosa, passa nello stato successivo, altrimenti rimani qui.
        if (fifo_wait_request_HH = '0') then
          ns <= SEARCH_HEADER;
        else
          ns <= SEARCH_FWV;
        end if;
      when SEARCH_HEADER =>  -- Sei in SEARCH_HEADER. Se l'header ricevuto è sbagliato vai in warning perchè significa che il pacchetto è corrotto. Altrimenti vai in ACQUISITION.
        if (not(CR_DATA_in = header)) then
          ns <= warning;
        elsif ((CR_DATA_in = header) and (fifo_wait_request_HH = '0')) then
          ns <= ACQUISITION;
        else
          ns <= SEARCH_HEADER;
        end if;
      when ACQUISITION =>  -- Sei in ACQUISITION. Se hai ricevuto tutto correttamente vai nello stato successivo, altrimenti in caso di errore vai in "WARNING".
        if (false_payload = '1') then
          ns <= warning;
        elsif (fast_payload_done = '1') then
          ns <= SEARCH_COFEE;
        elsif ((payload_done = '1') and (fifo_wait_request_HH = '0')) then
          ns <= SEARCH_COFEE;
        else
          ns <= ACQUISITION;
        end if;
      when SEARCH_COFEE =>  -- Sei in SEARCH_COFEE. Se il trailer ricevuto è sbagliato vai in warning perchè significa che il pacchetto è corrotto. Altrimenti vai in "SEARCH_CRC".
        if (not(CR_DATA_in = trailer)) then
          ns <= warning;
        elsif ((CR_DATA_in = trailer) and (fifo_wait_request_HH = '0')) then
          ns <= SEARCH_CRC;
        else
          ns <= SEARCH_COFEE;
        end if;
      when SEARCH_CRC =>  -- Sei in SEARCH_CRC. Se il CRC ricevuto è sbagliato vai in warning perchè significa che il pacchetto è corrotto. Altrimenti vai in "RESET" e predisponiti per la ricezione di un nuovo pacchetto.
        if (CR_DATA_in = estimated_CRC32) then
          ns <= RESET;
        else
          ns <= warning;
        end if;
      when REBOUND =>  -- Sei in REBOUND. Se il pacchetto ricevuto è lo start of packet vai allo stato successivi, altrimenti "rimbalza" allo stato di "SEARCH_SOP".
        if ((CR_DATA_in = start_of_packet) and (fifo_wait_request_HH = '0')) then
          ns <= SEARCH_LEN;
        elsif ((not(CR_DATA_in = start_of_packet)) and (fifo_wait_request_HH = '0')) then
          ns <= SEARCH_SOP;
        else
          ns <= REBOUND;
        end if;
      when warning =>  -- Sei in WARNING. Passa immediatamente allo stato di "RESET" e predisponiti per la ricezione di un nuovo pacchetto.
        ns <= RESET;
      when others =>  -- Sei in OTHERS. Significa che non sei in nessun stato definito per la nostra macchina. Vai immediatamente in "WARNING" perchè qualcosa è andato storto.
        ns <= warning;
    end case;
  end process;

  -- State Synchronization. Sincronizza lo stato attuale della macchina con il fronte di salita del clock.
  state_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (CR_RST_in = '1') then
        ps <= RESET;
      else
        ps <= ns;
      end if;
    end if;
  end process;

  -- Internal Signals Switch Data Flow. Interruttore generale per abilitare o disabilitare i segnali di "enable".
  internal_reset      <= '1' when ps = RESET         else '0';
  synch_enable        <= '1' when ps = SYNCH         else '0';
  start_packet_enable <= '1' when ps = SEARCH_SOP    else '0';
  length_enable       <= '1' when ps = SEARCH_LEN    else '0';
  fwv_enable          <= '1' when ps = SEARCH_FWV    else '0';
  header_enable       <= '1' when ps = SEARCH_HEADER else '0';
  payload_enable      <= '1' when ps = ACQUISITION   else '0';
  cofee_enable        <= '1' when ps = SEARCH_COFEE  else '0';
  crc_enable          <= '1' when ps = SEARCH_CRC    else '0';
  rebound_enable      <= '1' when ps = REBOUND       else '0';
  warning_enable      <= '1' when ps = warning       else '0';

  -- Output Process. Processo per la determinzazione dei valori sulle porte d'uscita del Config_Receiver.
  output_proc : process (ps, synch_enable_R, synch_pulse, synch_pulse_HH, start_packet_enable_R, rebound_enable_R, length_enable_R, fwv_enable_R, header_enable_R, payload_enable_WRT, false_payload, data, address, data_valid, cofee_enable_R, crc_enable_R, warning_enable_R, header_missed, cofee_missed, crc_missed)
  begin
    case ps is
      when RESET =>
        CR_FIFO_READ_EN_out <= '0';
        CR_WARNING_out      <= (others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SYNCH =>
        CR_FIFO_READ_EN_out <= synch_enable_R;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SEARCH_SOP =>
        CR_FIFO_READ_EN_out <= start_packet_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SEARCH_LEN =>
        CR_FIFO_READ_EN_out <= length_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SEARCH_FWV =>
        CR_FIFO_READ_EN_out <= fwv_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SEARCH_HEADER =>
        CR_FIFO_READ_EN_out <= header_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when ACQUISITION =>
        CR_FIFO_READ_EN_out <= payload_enable_WRT;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= data;
        CR_ADDRESS_out      <= address;
        CR_DATA_VALID_out   <= data_valid;
      when SEARCH_COFEE =>
        CR_FIFO_READ_EN_out <= cofee_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when SEARCH_CRC =>
        CR_FIFO_READ_EN_out <= '0';
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when REBOUND =>
        CR_FIFO_READ_EN_out <= rebound_enable_R or synch_pulse_HH;
        CR_WARNING_out      <= (2 => fwv_missed, others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
      when warning =>
        CR_FIFO_READ_EN_out <= '0';
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
        if ((false_payload = '1') or (crc_missed = '1')) then
          CR_WARNING_out <= "001";
        elsif ((header_missed = '1') or (cofee_missed = '1')) then
          CR_WARNING_out <= "010";
        else
          CR_WARNING_out <= "100";
        end if;
      when others =>
        CR_FIFO_READ_EN_out <= '0';
        CR_WARNING_out      <= (others => '0');
        CR_DATA_out         <= (others => '0');
        CR_ADDRESS_out      <= (others => '0');
        CR_DATA_VALID_out   <= '0';
    end case;
  end process;

  -----------------------
  -- Signal Processing --
  -----------------------

  -- Save the Length of Packet. In questo processo si vuole memorizzare la lunghezza del pacchetto. Il valore è tenuto fino ad un nuovo stato di "RESET".
  leng_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        length_packet <= (others => '0');
      elsif (length_enable_R = '1') then
        length_packet <= CR_DATA_in;
      end if;
    end if;
  end process;

  -- Search the Firmware version of HPS. In questo processo si vuole memorizzare l'occorrenza di una versione errate del Firmware di modo che quando andremo in "SEARCH_HEADER" lo segnaliamo alzando il bit di errore generico del sulla porta "CR_WARNING_out".
  fwv_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        fwv_missed <= '0';
      elsif ((fwv_enable_R = '1') and (not(CR_DATA_in = CR_FWV_in))) then
        fwv_missed <= '1';
      end if;
    end if;
  end process;

  -- Search the "header" of Packet. In questo processo si vuole memorizzare l'occorrenza di un header errato di modo che quando andremo in "WARNING" sapremo riconoscere il tipo di errore che ci ha portati in quello stato.
  head_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        header_missed <= '0';
      elsif ((header_enable_R = '1') and (not(CR_DATA_in = header))) then
        header_missed <= '1';
      end if;
    end if;
  end process;

  -- L'acquisizione del payload nonché la verifica della sua correttezza viene fatta nei successivi due processi chiamati "core0" e "core1".
  -- Acquisition of payolaod's Packet core0. Questo processo è in grado di discriminare la word di dato dalla word di parità del payload attraverso un segnale che viene chiamato download_phase.
  Acq_Payload_core0_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        data_RX           <= (others => '0');
        address_RX        <= (others => '0');
        download_phase    <= "00";
        estimated_parity  <= (others => '0');
        payload_done      <= '0';
        fast_payload_done <= '0';
      elsif ((payload_enable_WRT = '1') and ((download_phase = "00") or (download_phase = "11"))) then
        data_RX             <= CR_DATA_in;
        download_phase      <= "01";  -- Nella phase "00" e "11" acquisisci il dato del payload e stima la sua parità.
        estimated_parity(0) <= parity8bit("EVEN", CR_DATA_in(7 downto 0));
        estimated_parity(1) <= parity8bit("EVEN", CR_DATA_in(15 downto 8));
        estimated_parity(2) <= parity8bit("EVEN", CR_DATA_in(23 downto 16));
        estimated_parity(3) <= parity8bit("EVEN", CR_DATA_in(31 downto 24));
      elsif ((payload_enable_WRT = '1') and (download_phase = "01")) then
        address_RX          <= CR_DATA_in(15 downto 0);
        parity              <= CR_DATA_in(31 downto 24);
        download_phase      <= "11";  -- Nella phase "01" acquisisci l'indirizzo del registro e la parità. Inoltre stima la parità della word stessa.
        estimated_parity(4) <= parity8bit("EVEN", CR_DATA_in(7 downto 0));
        estimated_parity(5) <= parity8bit("EVEN", CR_DATA_in(15 downto 8));
      elsif ((payload_enable = '1') and (end_count_WRTimer_R = '1')) then
        if (fifo_wait_request_d = '0') then
          fast_payload_done <= '1';  -- Se il segnale di "end_count" si alza, considera l'acquisizione dati terminata con successo. E visto che "fifo_wait_request_d" è alto, passa fin da subito nello stato successivo della macchina.
        else
          payload_done <= '1';  -- Se il segnale di "end_count" si alza, considera l'acquisizione dati terminata con successo.
        end if;
      end if;
    end if;
  end process;

  -- Acquisition of payolaod's Packet core1. Questo processo inoltra il dato acquisito verso l'uscita (se la stima della parità coincide con la parità) ed alza il bit "data_ready".
  Acq_Payload_core1_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        data          <= (others => '0');
        address       <= (others => '0');
        data_ready    <= '0';
        false_payload <= '0';
      elsif ((payload_enable = '1') and ((download_phase = "00") or (download_phase = "01"))) then
        data_ready <= '0';  -- Il data_ready dev'essere a zero in tutte le phase tranne "11", altrimenti non potrei lanciare l'impulso di "data_valid" all'occorrenza.
      elsif ((payload_enable = '1') and (download_phase = "11")) then  -- La valutazione della parità va fatta esclusivamente nella phase "11" poichè è lì che abbiamo a disposizione i dati raccolti nelle phase "00" e "01".
        if (estimated_parity = parity) then
          data_ready <= '1';
          data       <= data_RX;
          address    <= address_RX;
        else
          false_payload <= '1';  -- Se la parità stimata non coincide con quella ricevuta, segnala l'errore alzando il bit "false_payload".
        end if;
      end if;
    end if;
  end process;

  -- Search the "cofee" of Packet. In questo processo si vuole memorizzare l'occorrenza di un trailer errato di modo che quando andremo in "WARNING" sapremo riconoscere il tipo di errore che ci ha portati in quello stato.
  cofee_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        cofee_missed <= '0';
      elsif ((cofee_enable_R = '1') and (not(CR_DATA_in = trailer))) then
        cofee_missed <= '1';
      end if;
    end if;
  end process;

  -- Search the "crc" of Packet. In questo processo si vuole memorizzare l'occorrenza di un CRC errato di modo che quando andremo in "WARNING" sapremo riconoscere il tipo di errore che ci ha portati in quello stato.
  crc_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        crc_missed <= '0';
      elsif ((crc_enable_R = '1') and (not(CR_DATA_in = estimated_CRC32))) then
        crc_missed <= '1';
      end if;
    end if;
  end process;

  -- Flip Flop D per ritardare il segnale di "Wait_Request" della FIFO. Lo scopo è quello di evitare situazione potenzialmente dannose per la macchina causate da Wait_Request estremamente corti.
  delay_Wait_Request_proc : process (CR_CLK_in)
  begin
    if rising_edge(CR_CLK_in) then
      if (internal_reset = '1') then
        fifo_wait_request_d <= '0';
      else
        fifo_wait_request_d <= fifo_wait_request_HH;
      end if;
    end if;
  end process;


end Behavior;
