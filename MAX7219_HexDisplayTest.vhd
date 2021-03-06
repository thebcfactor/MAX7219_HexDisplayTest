---------------------------------------------------------
--	"MAX7219 Hex Display Test"
--
--	By:  Brian Christian
--	Date:  September 24, 2018
--
--	Description:
--		Display "01234567" on a MAX7219 8-digit 7-segment
--		board.
---------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity MAX7219_HexDisplayTest is

	port(
			-- SPI Output (to MAX7219 Module)
			GPIO			: out	std_logic_vector(12 downto 10);	-- 12 = Data, 11 = /Load, 10 = Clock
			
			-- 50MHz On-Board Oscillator
			CLOCK_50_B5B	: in	std_logic;
			
			-- Reset Button
			CPU_RESET_n		: in	std_logic
		);

end entity;


architecture rtl of MAX7219_HexDisplayTest is


	-- SERIAL CONTROLLER SIGNALS
	-- Serial Data Output
	signal spi_out			: std_logic;	-- Serial Data Out (Valid on rising edge of serial clock.)
	signal spi_clk			: std_logic;	-- Serial Clock Out
	signal spi_sel			: std_logic;	-- Serial Select Out
	
	-- Parallel Data Interface
	signal spi_data			: std_logic_vector(15 downto 0);	-- Parallel Data In
	signal spi_load			: std_logic;						-- Load Parallel Data Strobe
	signal spi_busy			: std_logic;						-- Transfer In Progress Flag
	
	-- Internal Control Signals
	signal spi_buffer		: std_logic_vector(15 downto 0);	-- Output Buffer
	signal spi_count		: integer range 0 to 17;			-- Output Bit Position Counter
	signal spi_start		: std_logic;						-- Start Transfer Flag
	
	-- Command Signals
	type cmd_type is array (0 to 20) of std_logic_vector(15 downto 0);
	signal cmd				: cmd_type;
	signal cmd_count		: integer range 0 to 20;
	
	-- Clock Signals
	signal clk				: std_logic;				-- Serial Master Clock
	signal clk_count		: integer range 0 to 50000000;	-- Clock Divider Counter
	
	
begin
	
	
	-- EXTERNAL SIGNAL CONNECTIONS
		-- SPI Bus
		GPIO(12) <= spi_out;
		GPIO(10) <= spi_clk;
		GPIO(11) <= spi_sel;
	
	
	-- CLOCK DIVIDER
	-- Generate a 1MHz clock. (Sets the CPI output clock.)
	process(CLOCK_50_B5B)
	begin
		if (rising_edge(CLOCK_50_B5B)) then
			if (clk_count < 25) then
				clk_count <= clk_count + 1;
			else
				clk_count <= 0;
				clk <= not clk;
			end if;
		end if;
	end process;
	
	
	-- START TRIGGER
	-- On 'spi_load' signal, trigger the SPI Contol to start.
	process(spi_load)
	begin
		if (spi_busy = '1') then			-- If the SPI is busy, ignore 'spi_load' strobe and
			spi_start <= '0';				-- clear 'spi_start'. (This creates a one-shot 'spi_start' strobe.)
		elsif (rising_edge(spi_load)) then	-- If the SPI is not busy and 'spi_load' is issued,
			spi_start <= '1';				-- set the 'spi_start' flag.
		end if;
	end process;
	
	
	-- INPUT LATCH
	-- On 'spi_load' signal, latch the input data to the SPI output buffer.
	process(spi_load)
	begin
		if (rising_edge(spi_load)) then		-- On rising edge of 'spi_load',
			spi_buffer <= spi_data;			-- move data to output buffer.
		end if;
	end process;
	
	
	-- SPI BIT COUNTER
	-- On start trigger, count backwards through 16 bits of data.
	process(clk)
	begin
		if (falling_edge(clk)) then			-- On the falling edge of the clock (this keeps the SPI serial
											-- data aligned on rising_edge of SPI output clock.),
			if (spi_start = '1') then		-- On a 'start' condition,
				spi_busy <= '1';			-- mark system as busy and
				spi_count <= 15;			-- set the bit counter to 15 to start the counter.
			elsif (spi_count = 0) then		-- If the bit counter is 0,
				spi_busy <= '0';			-- stop counting and clear the busy flag.
			else							-- Otherwise,
				spi_count <= spi_count - 1;	-- decrement the counter by 1 each clock cycle.
			end if;
		end if;
	end process;
	
	
	-- OUTPUT BUFFER
	-- Place a bit on the SPI output determined by bit counter.
	spi_out <= spi_buffer(spi_count);
	
	
	-- OUTPUT CLOCK
	-- Only enable the SPI output clock when the system is running, otherwise hold the SPI output clock low.
	spi_clk <= clk when (spi_busy = '1') else '0';
	
	
	-- OUTPUT SELECT
	-- Assert the SPI select line only while the system is running.
	spi_sel <= not spi_busy;
	
	
	-- COMMAND SEQUENCER
	-- Sequence command/data to be sent over the SPI bus.
	process(clk)
	begin
		if (CPU_RESET_n = '0') then					-- When a reset occurrs,
			cmd_count <= 0;						-- set pointer to first command.
		elsif (rising_edge(clk)) then			-- On each rising edge of clock,
			if (spi_busy = '0') then			-- run through command list only if SPI bus is not busy. 
				if (cmd_count = 11) then		-- When the counter get to 12,
					cmd_count <= 11;			-- hold at 12 to stop counter.
				else							-- Otherwise,
					cmd_count <= cmd_count + 1;	-- Increment command counter and
				end if;
				spi_load <= '1';				-- Send the SPI Load stobe.
			else								-- If the SPI bus is busy,
				spi_load <= '0';				-- negate the SPI Load stobe.
			end if;
		end if;
	end process;
	
	-- Place command for transmission over SPI bus.
	spi_data <= cmd(cmd_count);
	
	-- Command List
	cmd(00) <= x"0C01";	-- Turn display on.
	cmd(01) <= x"0A0F";	-- Set brightness to max intensity.
	cmd(02) <= x"0900";	-- Turn Decode Mode off. (Allows individulal segment to be address. A necessity for
						-- displaying hexadecimal codes.)
	cmd(03) <= x"0B07";	-- Enable displaying of all 8 digits.
	cmd(04) <= x"087E";	-- Set digit 8 to display a "0".
	cmd(05) <= x"0730";	-- Set digit 7 to display a "1".
	cmd(06) <= x"066D";	-- Set digit 6 to display a "2".
	cmd(07) <= x"0579";	-- Set digit 5 to display a "3".
	cmd(08) <= x"0433";	-- Set digit 4 to display a "4".
	cmd(09) <= x"035B";	-- Set digit 3 to display a "5".
	cmd(10) <= x"025F";	-- Set digit 2 to display a "6".
	cmd(11) <= x"0170";	-- Set digit 1 to display a "7".
	
	
end rtl;
