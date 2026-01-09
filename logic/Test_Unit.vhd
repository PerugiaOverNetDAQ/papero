----------------------------------------------------------------------------------
--------  UNITA' DI TEST DEL SISTEMA DAQ PER GENERARE DATI PSEUDOCASUALI  --------
----------------------------------------------------------------------------------
--!@file Test_Unit.vhd
--!@brief Generatore di dati pseudocasuali (tramite algoritmo PRBS) utilizzati per verificare il funzionamento della sola scheda DAQ
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;

use work.paperoPackage.all;
use work.basic_package.all;


--!@copydoc Test_Unit.vhd
entity Test_Unit is
  port(
    iCLK            : in  std_logic;    -- Porta per il clock
    iRST            : in  std_logic;    -- Porta per il reset
    iEN             : in  std_logic;  -- Porta per l'abilitazione della unità di test
    iSETTING_CONFIG : in  std_logic_vector(1 downto 0);  -- Configurazione modalità operativa: "01"-->dati pseudocasuali generati con un tempo pseudocasuale, "10" dati pseudocasuali generati negli istanti di trigger, "11" dati pseudocasuali generati di continuo (rate massima)
    iSETTING_LENGTH : in  std_logic_vector(31 downto 0);  -- Lunghezza del pacchetto --> Number of 32-bit payload words + 10 
    iTRIG           : in  std_logic;  -- Ingresso per il segnale di trigger proveniente dalla trigBusyLogic
    oDATA           : out std_logic_vector(31 downto 0);  -- Numero binario a 32 bit pseudo-casuale
    oDATA_VALID     : out std_logic;  -- Segnale che attesta la validità dei dati in uscita dalla Test_Unit. Se oDATA_VALID=1 --> il valore di "oDATA" è consistente
    oTEST_BUSY      : out std_logic  -- La Test_Unit è impegnata e non può essere interrotta, altrimenti il pacchetto dati verrebbe incompleto
    );
end Test_Unit;


--!@copydoc Test_Unit.vhd
architecture Behavior of Test_Unit is
  -- Dichiarazione degli stati della FSM
  type tStatus is (RESET, STANDBY, COUNT, RESTART_COUNT);  -- La Test_Unit è una macchina a stati costituita da 4 stati.
  signal sPS, sNS : tStatus;  -- PS= stato attuale, NS=stato prossimo.

  -- Set di segnali utili per interconnetere i vari moduli del Top-Level
  signal sSettingConfig : std_logic_vector(1 downto 0);  -- Configurazione modalità operativa
  signal sPRBS8_en      : std_logic;    -- Abilitazione del modulo PRBS8
  signal sPRBS8_out     : std_logic_vector(7 downto 0);  -- Valore di fine conteggio del contatore
  signal sTrig          : std_logic;  -- Segnale di trigger proveniente dalla trigBusyLogic
  signal sTrig_R        : std_logic;  -- Impulso di trigger proveniente dalla trigBusyLogic
  signal sStopValue     : std_logic_vector(15 downto 0);  -- Valore di fine conteggio del contatore utile per generare un intervallo temporale casuale tra l'uscita di un pachetto e il successivo
  signal sCounter       : std_logic_vector(15 downto 0);  -- Contatore per abilitare il PRBS32. Permette di creare un tempo di invio aleatorio tra un dato pseudocasuale e il successivo
  signal sSop           : std_logic;  -- Start of packet in modalità operativa 1 della Test_Unit
  constant cGND         : std_logic := '0';              -- Massa

  -- Set di segnali paralleli ai tre circuiti per la generazione di dati pseudocasuali
  signal sEN1          : std_logic;  -- Segnale per l'abilitazione della modalità operativa "01" in cui i dati pseudocasuali sono generati con un tempo pseudocasuale
  signal sEN2          : std_logic;  -- Segnale per l'abilitazione della modalità operativa "10" in cui i dati pseudocasuali sono generati negli istanti di trigger
  signal sEN3          : std_logic;  -- Segnale per l'abilitazione della modalità operativa "11" in cui i dati pseudocasuali sono generati di continuo (rate massima)
  signal sEN1_R        : std_logic;  -- Impulso generato sul fronte di salita del segnale di sEN1
  signal sEN2_R        : std_logic;  -- Impulso generato sul fronte di salita del segnale di sEN2
  signal sEN3_R        : std_logic;  -- Impulso generato sul fronte di salita del segnale di sEN3
  signal sEN2_F        : std_logic;  -- Impulso generato sul fronte di discesa del segnale di sEN2
  signal sPRBS32_out1  : std_logic_vector(31 downto 0);  -- Numero binario a 32 bit pseudo-casuale in uscita dal PRBS1.
  signal sData1        : std_logic_vector(31 downto 0);  -- Numero binario pseudo-casuale a 32 bit generato nella prima modalità
  signal sData2        : std_logic_vector(31 downto 0);  -- Numero binario pseudo-casuale a 32 bit generato nella prima modalità
  signal sData3        : std_logic_vector(31 downto 0);  -- Numero binario pseudo-casuale a 32 bit generato nella prima modalità
  signal sBusy1        : std_logic;  -- La Test_Unit in modalità '1' è impegnata e non può essere interrotta
  signal sBusy2        : std_logic;  -- La Test_Unit in modalità '2' è impegnata e non può essere interrotta
  signal sBusy3        : std_logic;  -- La Test_Unit in modalità '3' è impegnata e non può essere interrotta
  signal sDataValid1   : std_logic;  -- Segnale che attesta la validità dei dati in uscita dalla Test_Unit in modalità operativa 1
  signal sDataValid2   : std_logic;  -- Segnale che attesta la validità dei dati in uscita dalla Test_Unit in modalità operativa 2
  signal sDataValid3   : std_logic;  -- Segnale che attesta la validità dei dati in uscita dalla Test_Unit in modalità operativa 3
  signal sWordCounter1 : std_logic_vector(31 downto 0);  -- Contatore del numero di word inviate dalla Test_Unit in modalità operativa 1
  signal sWordCounter2 : std_logic_vector(31 downto 0);  -- Contatore del numero di word inviate dalla Test_Unit in modalità operativa 2
  signal sPRBS32_en    : std_logic;  -- Abilitazione del modulo PRBS32 in modalità operativa 1
  signal sPRBS32_en2   : std_logic;  -- Abilitazione del modulo PRBS32 in modalità operativa 2
  signal sPRBS32_en3   : std_logic;  -- Abilitazione del modulo PRBS32 in modalità operativa 3
  signal sPacket_full1 : std_logic;  -- Flag per segnalare che il numero di word generate è sufficiente per formare un pacchetto in modalità operativa 1
  signal sLength1      : std_logic_vector(31 downto 0);  -- Numero di word necessarie per formare un pacchetto in modalità operativa 1

  -- Set di segnali il cui valore indica la presenza in un preciso stato della macchina a stati.
  signal sInternalReset_ps      : std_logic;  -- '1' solo se PS=RESET
  signal sStandbyEnable_ps      : std_logic;  -- '1' solo se PS=STANDBY
  signal sCountEnable_ps        : std_logic;  -- '1' solo se PS=COUNT
  signal sRestartCountEnable_ps : std_logic;  -- '1' solo se PS=RESTART_COUNT
  signal sInternalReset_ns      : std_logic;  -- '1' solo se NS=RESET
  signal sStandbyEnable_ns      : std_logic;  -- '1' solo se NS=STANDBY
  signal sCountEnable_ns        : std_logic;  -- '1' solo se NS=COUNT
  signal sRestartCountEnable_ns : std_logic;  -- '1' solo se NS=RESTART_COUNT

  -- Set di impulsi generati sul fronte di salita (R) e di discesa (F) dai rispettivi segnali di "enable".
  signal sInternalReset_ps_R      : std_logic;
  signal sStandbyEnable_ps_R      : std_logic;
  signal sCountEnable_ps_R        : std_logic;
  signal sRestartCountEnable_ps_R : std_logic;
  signal sInternalReset_ns_R      : std_logic;
  signal sStandbyEnable_ns_R      : std_logic;
  signal sCountEnable_ns_R        : std_logic;
  signal sCountEnable_ns_F        : std_logic;
  signal sRestartCountEnable_ns_R : std_logic;


begin
  -- Processo per evitare che qualcuno possa cambiare modalità operativa mentre la Test_Unit risulta impegnata
  setting_config_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if ((sBusy1 = '0') and (sBusy2 = '0')) then
        sSettingConfig <= iSETTING_CONFIG;
      end if;
    end if;
  end process;

  -- Assegnazione segnali interni
  sStopValue <= not (sPRBS8_out & x"FF");  -- Utilizzeremo come valore di fine conteggio un multiplo di 256 (MAX= 1,3 ms). Inoltre prenderemo l'uscita del PRBS8 negata, altrimenti non avremmo potuto usufruire della quantità "0x0000"
  sEN1       <= iEN and sSettingConfig(0) and (not sSettingConfig(1));  -- Generazione del segnale di Enable per la prima modalità operativa della Test_Unit
  sEN2       <= iEN and (not sSettingConfig(0)) and sSettingConfig(1);  -- Generazione del segnale di Enable per la seconda modalità operativa della Test_Unit
  sEN3       <= iEN and sSettingConfig(0) and sSettingConfig(1);  -- Generazione del segnale di Enable per la terza modalità operativa della Test_Unit
  sTrig      <= (sEN2 and iTRIG);  -- Segnale usato per trasportare il trigger iniettato sulla porta "iTRIG"

  -- Instanziamento dello User Edge Detector per generare gli impulsi (di 1 ciclo di clock) che segnalano il passaggio da uno stato all'altro.
  rise_edge_implementation : edge_detector_2
    generic map(
      channels => 12,
      R_vs_F   => '0'
      )
    port map(
      iCLK      => iCLK,
      iRST      => cGND,
      iD(0)     => sEN1,
      iD(1)     => sEN2,
      iD(2)     => sEN3,
      iD(3)     => sInternalReset_ps,
      iD(4)     => sStandbyEnable_ps,
      iD(5)     => sCountEnable_ps,
      iD(6)     => sRestartCountEnable_ps,
      iD(7)     => sInternalReset_ns,
      iD(8)     => sStandbyEnable_ns,
      iD(9)     => sCountEnable_ns,
      iD(10)    => sRestartCountEnable_ns,
      iD(11)    => sTrig,
      oEDGE(0)  => sEN1_R,
      oEDGE(1)  => sEN2_R,
      oEDGE(2)  => sEN3_R,
      oEDGE(3)  => sInternalReset_ps_R,
      oEDGE(4)  => sStandbyEnable_ps_R,
      oEDGE(5)  => sCountEnable_ps_R,
      oEDGE(6)  => sRestartCountEnable_ps_R,
      oEDGE(7)  => sInternalReset_ns_R,
      oEDGE(8)  => sStandbyEnable_ns_R,
      oEDGE(9)  => sCountEnable_ns_R,
      oEDGE(10) => sRestartCountEnable_ns_R,
      oEDGE(11) => sTrig_R
      );

  -- Instanziamento dello User Edge Detector per generare gli impulsi di "synch_pulse" per risincronizzare l'uscita della FIFO con l'ingresso del ricevitore quando la FIFO passa da vuota a non vuota.
  fall_edge_implementation : edge_detector_2
    generic map(
      channels => 1,
      R_vs_F   => '1'
      )
    port map(
      iCLK     => iCLK,
      iRST     => cGND,
      iD(0)    => sCountEnable_ns,
      oEDGE(0) => sCountEnable_ns_F
      );

  -- Generazione del valore di fine conteggio
  compute_end_count : PRBS8
    port map(
      iCLK      => iCLK,
      iRST      => sInternalReset_ps,
      iEN => sPRBS8_en,
      oPRBS     => sPRBS8_out
      );

  -- Generazione del dato pseudo-casuale a 32 bit nella PRIMA modalità operativa
  compute_output_data1 : PRBS32
    port map(
      iCLK       => iCLK,
      iRST       => sInternalReset_ps,
      iEN => sPRBS32_en,
      oPRBS      => sPRBS32_out1
      );

  -- Generazione del dato pseudo-casuale a 32 bit nella SECONDA modalità operativa
  compute_output_data2 : PRBS32
    port map(
      iCLK       => iCLK,
      iRST       => sInternalReset_ps,
      iEN => sPRBS32_en2,
      oPRBS      => sData2
      );

  -- Generazione del dato pseudo-casuale a 32 bit nella TERZA modalità operativa
  compute_output_data3 : PRBS32
    port map(
      iCLK       => iCLK,
      iRST       => sInternalReset_ps,
      iEN => sPRBS32_en3,
      oPRBS      => sData3
      );


  -- Next State Evaluation
  delta_proc : process (sPS, sEN1, sCounter, sStopValue, sPacket_full1)
  begin
    case sPS is
      when RESET =>                     -- Sei in RESET
        if (sEN1 = '1') then
          sNS <= COUNT;  -- Se la Test_Unit viene abilitata, passa a COUNT
        else
          sNS <= STANDBY;               --   Altrimenti vai in STANDBY
        end if;
      when STANDBY =>                   -- Sei in STANDBY
        if ((sEN1 = '1') and (sCounter = sStopValue)) then
          sNS <= RESTART_COUNT;  -- Se la Test_Unit viene abilitata ed il conteggio si trova nel suo valore massimo, vai in RESTART
        elsif ((sEN1 = '1') and (not (sCounter = sStopValue))) then
          sNS <= COUNT;  -- Se non si trova nel suo valore massimo passa a COUNT
        else
          sNS <= STANDBY;  -- Altrimenti, senza abilitazione, rimani qui in attesa senza fare niente
        end if;
      when COUNT =>                     -- Sei in COUNT
        if (sEN1 = '0') then
          sNS <= STANDBY;  -- Se la Test_Unit viene disabilitata, torna in STANDBY
        elsif (sCounter = sStopValue) then
          sNS <= RESTART_COUNT;  -- Se la Test_Unit è ancora attiva e il conteggio ha raggiunto il suo valore massimo, vai in RESTART
        else
          sNS <= COUNT;  -- Altrimenti, se non siamo al valore massimo, rimani in COUNT
        end if;
      when RESTART_COUNT =>             -- Sei in RESTART_COUNT
        if ((sEN1 = '0') and (sPacket_full1 = '1')) then
          sNS <= STANDBY;  -- Se la Test_Unit viene disabilitata, torna in STANDBY
        elsif ((sCounter = sStopValue) or (sPacket_full1 = '0')) then  -- or (sPacket_full1 = '0') ----- (sCounter = sStopValue) or
          sNS <= RESTART_COUNT;  -- Se la Test_Unit è ancora attiva e il conteggio è ancora nel suo valore massimo, rimani in RESTART_COUNT
        else
          sNS <= COUNT;  -- Altrimenti, se non siamo al valore massimo, ricominca a contare daccapo
        end if;
      when others =>  -- Se ci troviamo in uno stato non definito, passa a RESET
        sNS <= RESET;
    end case;
  end process;


  -- State Synchronization. Sincronizza lo stato attuale della macchina con il fronte di salita del clock.
  state_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (iRST = '1') then
        sPS <= RESET;
      else
        sPS <= sNS;
      end if;
    end if;
  end process;


  -- Internal Signals Switch Data Flow. Interruttore generale per abilitare o disabilitare i segnali di "enable".
  sInternalReset_ps      <= '1' when sPS = RESET         else '0';
  sStandbyEnable_ps      <= '1' when sPS = STANDBY       else '0';
  sCountEnable_ps        <= '1' when sPS = COUNT         else '0';
  sRestartCountEnable_ps <= '1' when sPS = RESTART_COUNT else '0';
  sInternalReset_ns      <= '1' when sNS = RESET         else '0';
  sStandbyEnable_ns      <= '1' when sNS = STANDBY       else '0';
  sCountEnable_ns        <= '1' when sNS = COUNT         else '0';
  sRestartCountEnable_ns <= '1' when sNS = RESTART_COUNT else '0';


  -- Internal Process. Processo asincrono per la determinzazione dei valori dei segnali interni della Test_Unit.
  internal_proc : process (sPS, sEN1_R, sRestartCountEnable_ns_R, sRestartCountEnable_ns, sSop)
  begin
    case sPS is
      when RESET =>                     -- Sei in RESET
        sPRBS8_en  <= '0';  -- Se viene attivata la Test_Unit, estrai una nuova lunghezza temporale
        sPRBS32_en <= '0';
      when STANDBY =>                   -- Sei in STANDBY
        sPRBS8_en  <= '0';  -- Se viene attivata la Test_Unit o se il prossimo stato è RESTART, estrai una nuova lunghezza temporale
        sPRBS32_en <= sRestartCountEnable_ns_R;  -- se il prossimo stato è RESTART, estrai un nuovo dato
      when COUNT =>                     -- Sei in COUNT
        sPRBS8_en  <= '0';  -- se il prossimo stato è RESTART, estrai una nuova lunghezza temporale
        sPRBS32_en <= sRestartCountEnable_ns_R;  -- se il prossimo stato è RESTART, estrai un nuovo dato
      when RESTART_COUNT =>             -- Sei in RESTART_COUNT
        sPRBS8_en  <= sSop;  -- se è appena iniziata la trasmissiamo di un pacchetto, estrai una nuova lunghezza temporale
        sPRBS32_en <= sRestartCountEnable_ns;  -- se il prossimo stato è RESTART, estrai un nuovo dato
      when others =>                    -- Sei in uno stato non definito
        sPRBS8_en  <= '0';
        sPRBS32_en <= '0';
    end case;
  end process;


  -- Output Process. Processo asincrono per la determinzazione dei valori sulle porte d'uscita della Test_Unit.
  output_proc : process (sPS, sPRBS32_out1)
  begin
    case sPS is
      when RESET =>                     -- Sei in RESET
        sData1      <= (others => '1');  -- ATTENZIONE, l'attivazione del segnale di reset porta l'uscita dati "alta".
        sDataValid1 <= '0';
      when STANDBY =>                   -- Sei in STANDBY
        sData1      <= sPRBS32_out1;
        sDataValid1 <= '0';
      when COUNT =>                     -- Sei in COUNT
        sData1      <= sPRBS32_out1;
        sDataValid1 <= '0';
      when RESTART_COUNT =>             -- Sei in RESTART_COUNT
        sData1      <= sPRBS32_out1;
        sDataValid1 <= '1';  -- Attiva il segnale di Data_Valid se e solo se ci troviamo in RESTART_COUNT
      when others =>                    -- Sei in uno stato non definito
        sData1      <= sPRBS32_out1;
        sDataValid1 <= '0';
    end case;
  end process;


  ------------------------------
  -- Signal Processing  Mod 1 --
  ------------------------------

  -- Contatore per temporizzare l'invio dei dati verso l'esterno
  counter_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sCounter <= (others => '0');  -- Se siamo in RESET, azzera il contatore 
      elsif (((sCountEnable_ns_R = '1') or (sCountEnable_ps = '1')) and (sCountEnable_ns_F = '0')) then
        sCounter <= sCounter + 1;  -- Se il prossimo stato è COUNT oppure già ci siamo, incrementa il conteggio. Attenzione! in COUNT, ignora l'ultimo incremento
      elsif (sRestartCountEnable_ns_R = '1') then
        sCounter <= (others => '0');  -- Azzera il contatore ogni volta che stiamo per entrare nello stato RESTART_COUNT
      end if;
    end if;
  end process;

  -- Processo per il calcolo del numero di parole necessarie per formare un pacchetto
  length1_calculate_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if ((sEN1_R = '1') or (sPacket_full1 = '1') or (sPS = STANDBY)) then
        sLength1 <= iSETTING_LENGTH - 10;  -- Se qualcuno abilita la Test_Unit, oppure si è appena concluso l'invio dell'ultima word necessaria per formare un pacchetto, aggiorna lunghezza desiderata
      end if;
    end if;
  end process;

  -- Contatore per discretizzare l'invio dei dati in funzione della lunghezza desiderata, nella modalità operativa 1
  word_counter1_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sWordCounter1 <= (others => '0');  -- Se siamo in RESET, azzera il contatore    
        sPacket_full1 <= '0';
        sSop          <= '0';
      elsif (sRestartCountEnable_ns = '1') then
        if (sWordCounter1 < sLength1 - 1) then
          if (sWordCounter1 = 1) then
            sSop <= '1';
          else
            sSop <= '0';
          end if;

          sWordCounter1 <= sWordCounter1 + 1;  -- Se il prossimo stato è RESTART_COUNT e mi mancano almeno due parole per completare il pacchetto, continua ad incrementare il contatore delle word
          sPacket_full1 <= '0';
        else
          sWordCounter1 <= (others => '0');  -- Se il prossimo stato è RESTART_COUNT e mi manca una sola parola per completare il pacchetto, alza il flag "sPacket_full1" e riazzera il contatore delle word
          sPacket_full1 <= '1';
        end if;
      else
        sPacket_full1 <= '0';
      end if;
    end if;
  end process;

  -- Processo per il controllo del segnale di "sBusy1" della Test_Unit
  busy1_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sBusy1 <= '0';  -- Se siamo in RESET, la Test_Unit si può considerare libera
      elsif (sEN1 = '1') then
        sBusy1 <= '1';  -- Se qualcuno ha abilitato la Test_Unit, la stessa si può considerare occupata nel trasferimento di qualche dato
      elsif ((sEN1 = '0') and (sDataValid1 = '0')) then
        sBusy1 <= '0';  -- Se qualcuno ha disabilitato la Test_Unit ed è stato ultimato l'invio dell'ultima word necessaria per formare un pacchetto, possiamo considerare la Test_Unit libera
      end if;
    end if;
  end process;

  ------------------------------
  -- Signal Processing  Mod 2 --
  ------------------------------

  -- Processo per riempire la FIFO con una quantità di elementi rimanenti pari alla lunghezza del pacchetto
  word_counter2_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sWordCounter2 <= (others => '0');  -- Se siamo in RESET, azzera il contatore
        sPRBS32_en2   <= '0';
      elsif (sWordCounter2 > 0) then
        sWordCounter2 <= sWordCounter2 - 1;  -- Se il contatore delle parole mancanti è maggiore di zero, estrai un dato dal PRBS32 e decrementa il contatore stesso
        sPRBS32_en2   <= '1';
      elsif (sTrig_R = '1') then
        sWordCounter2 <= iSETTING_LENGTH - 10;  -- Se qualcuno abilita la Test_Unit, memorizza la lunghezza desiderata per il pacchetto
        sPRBS32_en2   <= '0';
      else
        sWordCounter2 <= (others => '0');  -- Altrimenti, resetta tutto
        sPRBS32_en2   <= '0';
      end if;
    end if;
  end process;

  -- Flip Flop D per ritardare il segnale di trigger "sDataValid2". Lo scopo è quello di sincronizzare il "DATA_VALID" con la generazione del dato in uscita dal PRBS32
  delay_sTrig_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sDataValid2 <= '0';
      else
        sDataValid2 <= sPRBS32_en2;
      end if;
    end if;
  end process;

  -- Processo per il controllo del segnale di "sBusy3" della Test_Unit
  busy2_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sBusy2 <= '0';
      elsif (sEN2 = '1') then
        sBusy2 <= '1';
      elsif ((sEN2 = '0') and (sDataValid2 = '0')) then
        sBusy2 <= '0';
      end if;
    end if;
  end process;

  ------------------------------
  -- Signal Processing  Mod 3 --
  ------------------------------

  -- Processo per riempire la FIFO con una quantità di elementi rimanenti pari alla lunghezza del pacchetto
  word_counter3_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sPRBS32_en3 <= '0';
      elsif (sEN3 = '1') then
        sPRBS32_en3 <= '1';
      else
        sPRBS32_en3 <= '0';
      end if;
    end if;
  end process;

  -- Flip Flop D per ritardare il segnale di trigger "sDataValid3". Lo scopo è quello di sincronizzare il "DATA_VALID" con la generazione del dato in uscita dal PRBS32
  delay_sDataValid3_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sDataValid3 <= '0';
      else
        sDataValid3 <= sPRBS32_en3;
      end if;
    end if;
  end process;

  -- Processo per il controllo del segnale di "sBusy3" della Test_Unit
  busy3_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (sInternalReset_ps = '1') then
        sBusy3 <= '0';
      elsif (sEN3 = '1') then
        sBusy3 <= '1';
      elsif ((sEN3 = '0') and (sDataValid3 = '0')) then
        sBusy3 <= '0';
      end if;
    end if;
  end process;


  -- Data Flow per il controllo delle porte d'uscita
  with sSettingConfig select
    oDATA <= sData1 when "01",
    sData2          when "10",
    sData3          when "11",
    (others => '0') when others;

  with sSettingConfig select
    oDATA_VALID <= sDataValid1 when "01",
    sDataValid2                when "10",
    sDataValid3                when "11",
    '0'                        when others;

  with sSettingConfig select
    oTEST_BUSY <= sBusy1 when "01",
    sBusy2               when "10",
    sBusy3               when "11",
    '0'                  when others;


end Behavior;


