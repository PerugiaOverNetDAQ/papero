--!@file FastData_Transmitter.vhd
--!@brief Trasmettitore di dati scientifici
--!@author Matteo D'Antonio, matteo.dantonio@studenti.unipg.it

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;
use work.paperoPackage.all;
use work.basic_package.all;


--!@copydoc FastData_Transmitter.vhd
entity FastData_Transmitter is
  generic(
    pGW_VER : std_logic_vector(31 downto 0)
    );
  port(
    iCLK         : in  std_logic;       -- Clock
    iRST         : in  std_logic;       -- Reset
    -- Enable
    iEN          : in  std_logic;  -- Abilitazione del modulo FastData_Transmitter
    -- Settings Packet
    oMETADATA_RD : out std_logic; -- Read for the metadata fifos
    iMETADATA_EMPTY : in  std_logic; -- Empty of metadata fifos
    iMETADATA    : in  tF2hMetadata;    --Packet header information
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
end FastData_Transmitter;


--!@copydoc FastData_Transmitter.vhd
architecture Behavior of FastData_Transmitter is
-- Dichiarazione degli stati della FSM
  type tStatus is (RESET, IDLE, SOP, LENG, FWV, TRIG_NUM, TRIG_TYPE, INT_TIME_0, INT_TIME_1, EXT_TIME_0, EXT_TIME_1, BIAS_SET, BIAS_CURRENT, PAYLOAD, TRAILER, CRC);
  signal sPS : tStatus;

-- Set di costanti utili per la risoluzione del pacchetto ricevuto.
  constant cStart_of_packet : std_logic_vector(31 downto 0) := x"BABA1A9A";  -- Start of packet
  constant cTrailer         : std_logic_vector(31 downto 0) := x"0BEDFACE";  -- Bad Face

-- Set di segnali interni per pilotare le uscite del FastData_Transmitter
  signal sFifoRe         : std_logic;  -- Segnale di "Read_Enable" della FIFO a monte del FastData_Transmitter
  signal sFifoData       : std_logic_vector(31 downto 0);  -- Segnale di "Data_Inutput" della FIFO a valle del FastData_Transmitter
  signal sFifoWe         : std_logic;  -- Segnale di "Write_Enable" della FIFO a valle del FastData_Transmitter
  signal sScientificData : std_logic_vector(31 downto 0);  -- Segnale di "Data_Output" della FIFO a monte del FastData_Transmitter
  signal sBusy           : std_logic;  -- Bit per segnalare se il trasmettitore è impegnato in un trasferimento dati. '0'-->ok, '1'--> busy
  signal sFsmError       : std_logic;  -- Segnale di errore della macchina a stati finiti. '0'-->ok, '1'--> errore: la macchina è finita in uno stato non precisato
  signal sDataStillAvail : std_logic;  -- Ci sono ancora parole nella FIFO a monte quando iEN = 0

-- Set di segnali utili per il Signal Processing.
  signal sLength          : std_logic_vector(31 downto 0);  --Lunghezza pacchetto
  signal sFifoReDel       : std_logic;  -- Segnale di "Read_Enable" della FIFO a monte del FastData_Transmitter ritardato di un ciclo di clock
  signal sDataCounter     : std_logic_vector(11 downto 0);  -- Contatore del numero di parole di payload scritte nella FIFO a valle del FastData_Transmitter
  signal sCRC32_rst       : std_logic;  -- Reset del modulo per il calcolo del CRC
  signal sCRC32_en        : std_logic;  -- Abilitazione del modulo per il calcolo del CRC
  signal sCRC32Data       : std_logic_vector(31 downto 0);
  signal sEstimated_CRC32 : std_logic_vector(31 downto 0);  -- Valutazione del codice a ridondanza ciclica CRC-32/MPEG-2: Header (except length) + Payload
  signal sPayloadEn       : std_logic;  -- Siamo su Payload

begin
  -- Assegnazione segnali interni del FastData_Transmitter alle porte di I/O
  oFIFO_RE   <= sFifoRe;
  oFIFO_DATA <= sScientificData when (sPayloadEn = '1') else
                sFifoData;
  sCRC32Data <= sScientificData when (sPayloadEn = '1') else
                sFifoData;
  oFIFO_WE        <= sFifoWe or sFifoReDel;
  sScientificData <= iFIFO_DATA;
  oBUSY           <= sBusy;
  oWARNING        <= sFsmError or sDataStillAvail;


  -- Calcola il CRC32 per il contenuto del pacchetto (eccetto per SoP, Len, and EoP)
  Calcolo_CRC32 : CRC32
    generic map(
      pINITIAL_VAL => x"FFFFFFFF"
      )
    port map(
      iCLK    => iCLK,
      iRST    => sCRC32_rst,
      iCRC_EN => sCRC32_en,
      iDATA   => sCRC32Data,
      oCRC    => sEstimated_CRC32
      );

  
  sFifoRe <= '1' when (iFIFO_EMPTY = '0' and iFIFO_AFULL = '0' and sPS = PAYLOAD and (sDataCounter < sLength)) else
             '0';
  -- Implementazione della macchina a stati
  StateFSM_proc : process (iCLK)
  begin
    if (rising_edge(iCLK)) then
      if (iRST = '1') then
        -- Stato di RESET. Si entra in questo stato solo se qualcuno dall'esterno alza il segnale di reset
        sFifoData       <= (others => '0');
        sFifoWe         <= '0';
        sDataCounter    <= (others => '0');  --(0=>'1', others => '0');
        sBusy           <= '1';
        sFsmError       <= '0';
        sDataStillAvail <= '0';
        sCRC32_rst      <= '1';
        sCRC32_en       <= '0';
        sPayloadEn      <= '0';
        oMETADATA_RD    <= '0';
        sPS             <= IDLE;
        sLength         <= (others => '0');

      else
        -- Valori di default che verranno sovrascritti, se necessario
        sFifoData    <= (others => '0');
        sFifoWe      <= '0';
        sDataCounter <= (others => '0');  --(0=>'1', others => '0');
        sBusy        <= '1';
        sCRC32_rst   <= '0';
        sCRC32_en    <= '0';
        sPayloadEn   <= '0';
        oMETADATA_RD <= '0';
        case (sPS) is
          -- Stato di IDLE. Il Trasmettitore si mette in attesa che la FIFO a monte abbia almeno una word da inviare e quella a valle disponga di almeno 4 posizioni libere
          when IDLE =>
            sBusy      <= '0';  -- Questo è l'unico stato in cui il trasmettitore si può considerare non impegnato in un trasferimento
            sCRC32_rst <= '1';
            if (iEN = '1') then
              if (iMETADATA_EMPTY = '0' and iFIFO_EMPTY = '0' and iFIFO_AFULL = '0') then
                sPS <= SOP;
                oMETADATA_RD   <= '1';
              else
                sPS <= IDLE;
              end if;
            else
              sDataStillAvail <= not iFIFO_EMPTY;
            end if;

          -- Stato di START-OF-PACKET. Inoltro della parola "BABA1A9A"
          when SOP =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= cStart_of_packet;
              sFifoWe   <= '1';
              sPS       <= LENG;
            else
              sPS <= SOP;
            end if;

          -- Stato di LENGTH. Inoltro della parola contenente la lunghezza del pacchetto: Payload 32-bit words + 12
          when LENG =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.pktLen;
              sFifoWe   <= '1';
              sPS       <= FWV;
              sLength   <= iMETADATA.pktLen - int2slv(cHDR_WORDS, sLength'length);
            else
              sPS <= LENG;
            end if;

          -- Stato di FIRMWARE-VERSION. Inoltro della parola contenente la Versione del Firmware in uso (SHA dell'ultimo commit)
          when FWV =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= pGW_VER;
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= TRIG_NUM;
            else
              sPS <= FWV;
            end if;

          -- Stato di TRIGGER-NUMBER. Inoltro della parola contenente il numero di trigger
          when TRIG_NUM =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.trigNum;
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= TRIG_TYPE;
            else
              sPS <= TRIG_NUM;
            end if;

          -- Stato di TRIGGER-TYPE. Inoltro della parola contenente il Detector-ID e il Trigger-ID
          when TRIG_TYPE =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.detId & iMETADATA.trigId;
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= INT_TIME_0;
            else
              sPS <= TRIG_TYPE;
            end if;

          -- Stato di INTERNAL-TIMESTAMP-MSW. Inoltro della "Most_Significant_Word" contenente il Timestamp calcolato all'interno dell'FPGA
          when INT_TIME_0 =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.intTime(63 downto 32);
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= INT_TIME_1;
            else
              sPS <= INT_TIME_0;
            end if;

          -- Stato di INTERNAL-TIMESTAMP-LSW. Inoltro della "Least_Significant_Word" contenente il Timestamp calcolato all'interno dell'FPGA
          when INT_TIME_1 =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.intTime(31 downto 0);
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= EXT_TIME_0;
            else
              sPS <= INT_TIME_1;
            end if;

          -- Stato di EXTERNAL-TIMESTAMP-MSW. Inoltro della "Most_Significant_Word" contenente il Timestamp calcolato all'esterno dell'FPGA
          when EXT_TIME_0 =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.extTime(63 downto 32);
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= EXT_TIME_1;
            else
              sPS <= EXT_TIME_0;
            end if;

          -- Stato di EXTERNAL-TIMESTAMP-LSW. Inoltro della "Least_Significant_Word" contenente il Timestamp calcolato all'esterno dell'FPGA
          when EXT_TIME_1 =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.extTime(31 downto 0);
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= BIAS_SET;
            else
              sPS <= EXT_TIME_1;
            end if;
            
          -- Send the bias settings metadata word
          when BIAS_SET =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.biasSet;
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= BIAS_CURRENT;
            else
              sPS <= BIAS_SET;
            end if;
          
          -- Send the bias currents metadata word
          when BIAS_CURRENT =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= iMETADATA.biasCur;
              sFifoWe   <= '1';
              sCRC32_en <= '1';
              sPS       <= PAYLOAD;
            else
              sPS <= BIAS_CURRENT;
            end if;

          -- Stato di PAYLOAD. Inoltro delle parole di payload dalla FIFO a monte a quella a valle rispetto al FastData_Transmitter
          when PAYLOAD =>
            sPayloadEn <= '1';
            sCRC32_en  <= sFifoRe;

            if (sFifoRe = '1') then
              sDataCounter <= sDataCounter + 1;
            else
              sDataCounter <= sDataCounter;
            end if;

            if (sDataCounter < sLength)then
              sPS <= PAYLOAD;
            else
              sPS <= TRAILER;
            end if;

          -- Stato di TRAILER. Inoltro della parola di trailer "0BEDFACE"
          when TRAILER =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= cTrailer;
              sFifoWe   <= '1';
              sPS       <= CRC;
            else
              sPS <= TRAILER;
            end if;

          -- Stato di CRC. Inoltro del CRC-32/MPEG-2 calcolato su tutto il pacchetto (tranne per Sop, Length e Trailer)
          when CRC =>
            if (iFIFO_AFULL = '0') then
              sFifoData <= sEstimated_CRC32;
              sFifoWe   <= '1';
              sPS       <= IDLE;
            else
              sPS <= CRC;
            end if;

          -- Stato non previsto.
          when others =>
            sFifoData <= (others => '0');
            sFifoWe   <= '0';
            sFsmError <= '1';
            sPS       <= IDLE;

        end case;
      end if;
    end if;
  end process;


  -- Flip Flop D per ritardare il segnale di "Read_Enable" della FIFO a monte del FastData_Transmitter. Lo scopo è quello di evitare di leggere il dato in uscita dalla FIFO quando questo non è ancora pronto.
  delay_Wait_Request_proc : process (iCLK)
  begin
    if rising_edge(iCLK) then
      if (iRST = '1') then
        sFifoReDel <= '0';
      else
        sFifoReDel <= sFifoRe;
      end if;
    end if;
  end process;


end Behavior;
