--
-- OpenAudioFPGA - Behringer X32 with Xilinx Spartan-3A (XC3S1400A): top level
-- Copyright 2025-2026 OpenMixerProject
-- https://github.com/OpenMixerProject/OpenAudioFPGA
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- version 3 as published by the Free Software Foundation.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
--
-- This file only contains what is specific to the Spartan-3A board:
--   * the pins (names as in x32_spartan.ucf)
--   * DCM, global clock buffers, RMII IO registers and DDR clock outputs (ip/)
-- Everything else is consoles/x32/x32_common.vhd and rtl/core.
--
-- What runs on the two RMII ports is a matter of the generics of
-- consoles/x32/x32_common.vhd.
--
-- AES67 (G_AES67): create_project.tcl reads the default below and adds the
-- AES67 sources (ext/AES67) exactly when it is true; its arguments aes67 /
-- noaes67 override it. The registers of the AES67 core are on the
-- control bus (SPI_nCS0, 0x90000000), like everything else.

library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.vcomponents.all;

entity x32_spartan is
	generic (
		G_AES50_PORTS	: natural range 0 to 2 := 1;
		G_AES67			: boolean := true				-- AES67 core on the port after the AES50 cores
	);
	port (
		FPGACLK					: in  std_logic;	-- 16 MHz

		-- CS2000 audio PLL
		PLL_OUT					: in  std_logic;
		PLL_AUX					: in  std_logic;
		PLL_IN					: out std_logic;
		PLL_nCS					: out std_logic;
		PLL_CCLK				: out std_logic;
		PLL_CDATA				: out std_logic;

		-- i.MX25
		SPI_nCS0				: in  std_logic;	-- control bus (SPIBone), R15 = IO_L02P_1/LDC1 (FPGA_SS0)
		SPI_nCS1				: out std_logic;	-- used as IRQ
		SPI_CLK					: in  std_logic;
		SPI_MOSI				: in  std_logic;
		SPI_MISO				: out std_logic;
		imx25_uart3_txd			: in  std_logic;
		imx25_uart3_rxd			: out std_logic;
		imx25_uart4_txd			: in  std_logic;
		imx25_uart4_rxd			: out std_logic;

		-- AD / DA boards
		AD0_RX					: in  std_logic;
		AD0_TX					: out std_logic;
		AD0_DATA0				: in  std_logic;
		AD0_DATA1				: in  std_logic;
		AD0_MCLK				: out std_logic;
		AD0_BCLK				: out std_logic;
		AD0_FSYNC				: out std_logic;
		AD1_RX					: in  std_logic;
		AD1_TX					: out std_logic;
		AD1_DATA0				: in  std_logic;
		AD1_DATA1				: in  std_logic;
		AD1_MCLK				: out std_logic;
		AD1_BCLK				: out std_logic;
		AD1_FSYNC				: out std_logic;
		AD_nRESET				: out std_logic;
		DA_RX					: in  std_logic;
		DA_TX					: out std_logic;
		DA_DATA0				: out std_logic;
		DA_DATA1				: out std_logic;
		DA_MCLK					: out std_logic;
		DA_BCLK					: out std_logic;
		DA_FSYNC				: out std_logic;
		DA_nRESET				: out std_logic;

		-- AUX converter (CS42438)
		AUX_AD					: in  std_logic;
		AUX_DA					: out std_logic;
		AUX_MCLK				: out std_logic;
		AUX_SCLK				: out std_logic;
		AUX_FSYNC				: out std_logic;
		AUX_CCLK				: out std_logic;
		AUX_CDATA				: out std_logic;
		AUX_nCS					: out std_logic;
		AUX_nRST				: out std_logic;

		-- expansion card
		CARD_RX					: in  std_logic;
		CARD_TX					: out std_logic;
		CARD_RDY				: in  std_logic;
		CARD_IN0				: in  std_logic;
		CARD_IN1				: in  std_logic;
		CARD_IN2				: in  std_logic;
		CARD_IN3				: in  std_logic;
		CARD_OUT0				: out std_logic;
		CARD_OUT1				: out std_logic;
		CARD_OUT2				: out std_logic;
		CARD_OUT3				: out std_logic;
		CARD_BCLK				: out std_logic;
		CARD_FSYNC				: out std_logic;

		-- DSPs
		DSP_DOUT0				: in  std_logic;
		DSP_DOUT1				: in  std_logic;
		DSP_POUT0				: in  std_logic;
		DSP_POUT1				: in  std_logic;
		DSP_DOUTAUX				: in  std_logic;
		DSP_DIN0				: out std_logic;
		DSP_DIN1				: out std_logic;
		DSP_DIN2				: out std_logic;
		DSP_DIN3				: out std_logic;
		DSP_DINAUX				: out std_logic;
		D_CLK					: out std_logic;
		D_FS					: out std_logic;
		D_CLK2					: out std_logic;
		D_FS2					: out std_logic;

		-- UltraNet
		P16_A_TXP				: out std_logic;
		P16_A_TXM				: out std_logic;
		P16_B_TXP				: out std_logic;
		P16_B_TXM				: out std_logic;

		-- AES50 A
		aes50a_rmii_crs_dv_in	: in  std_logic;
		aes50a_rmii_er_in		: in  std_logic;
		aes50a_rmii_rxd_0_in	: in  std_logic;
		aes50a_rmii_rxd_1_in	: in  std_logic;
		aes50a_rmii_clk_out		: out std_logic;
		aes50a_rmii_tx_en_out	: out std_logic;
		aes50a_rmii_txd_0_out	: out std_logic;
		aes50a_rmii_txd_1_out	: out std_logic;
		aes50a_phy_rst_n_out	: out std_logic;
		aes50a_clk_a_rx_in		: in  std_logic;
		aes50a_clk_b_rx_in		: in  std_logic;
		aes50a_clk_a_tx_out		: out std_logic;
		aes50a_clk_b_tx_out		: out std_logic;
		aes50a_clk_a_tx_en_out	: out std_logic;
		aes50a_clk_b_tx_en_out	: out std_logic;
		aes50a_clk_a_rx_nen_out	: out std_logic;
		aes50a_clk_b_rx_nen_out	: out std_logic;

		-- AES50 B
		aes50b_rmii_crs_dv_in	: in  std_logic;
		aes50b_rmii_er_in		: in  std_logic;
		aes50b_rmii_rxd_0_in	: in  std_logic;
		aes50b_rmii_rxd_1_in	: in  std_logic;
		aes50b_rmii_clk_out		: out std_logic;
		aes50b_rmii_tx_en_out	: out std_logic;
		aes50b_rmii_txd_0_out	: out std_logic;
		aes50b_rmii_txd_1_out	: out std_logic;
		aes50b_clk_a_rx_in		: in  std_logic;
		aes50b_clk_b_rx_in		: in  std_logic;
		aes50b_clk_a_tx_out		: out std_logic;
		aes50b_clk_b_tx_out		: out std_logic;
		aes50b_clk_a_tx_en_out	: out std_logic;
		aes50b_clk_b_tx_en_out	: out std_logic;
		aes50b_clk_a_rx_nen_out	: out std_logic;
		aes50b_clk_b_rx_nen_out	: out std_logic
	);
end entity x32_spartan;

architecture rtl of x32_spartan is
	signal clk_16MHz		: std_logic;
	signal clk_49_152MHz	: std_logic;
	signal clk_50MHz		: std_logic;
	signal clk_50MHz_inv	: std_logic;
	signal clk_100MHz		: std_logic;
	signal clk_24_576MHz	: std_logic;
	signal clk_12_288MHz	: std_logic;
	signal tdm_fs			: std_logic;

	signal pripll_rst		: std_logic;
	signal rst				: std_logic;
	signal conv_nrst		: std_logic;

	-- RMII: bit 0 = CRS_DV / TX_EN, bits 2 .. 1 = RXD / TXD
	signal aes50a_rmii_rxd	: std_logic_vector(2 downto 0);
	signal aes50a_rmii_txd	: std_logic_vector(2 downto 0);
	signal aes50b_rmii_rxd	: std_logic_vector(2 downto 0);
	signal aes50b_rmii_txd	: std_logic_vector(2 downto 0);

	-- the two network ports of x32_common (0 = A, 1 = B)
	signal rmii_crs_dv		: std_logic_vector(1 downto 0);
	signal rmii_rxd			: std_logic_vector(3 downto 0);
	signal rmii_tx_en		: std_logic_vector(1 downto 0);
	signal rmii_txd			: std_logic_vector(3 downto 0);
	signal phy_rst_n		: std_logic_vector(1 downto 0);
	signal clk_a_rx			: std_logic_vector(1 downto 0);
	signal clk_a_tx			: std_logic_vector(1 downto 0);
	signal clk_a_tx_en		: std_logic_vector(1 downto 0);
	signal clk_a_rx_nen		: std_logic_vector(1 downto 0);
	signal clk_b_rx			: std_logic_vector(1 downto 0);
	signal clk_b_tx			: std_logic_vector(1 downto 0);
	signal clk_b_tx_en		: std_logic_vector(1 downto 0);
	signal clk_b_rx_nen		: std_logic_vector(1 downto 0);

	signal card_out			: std_logic_vector(3 downto 0);
	signal dsp_dout			: std_logic_vector(3 downto 0);
	signal dsp_din			: std_logic_vector(3 downto 0);
	signal host_irq			: std_logic;
begin
	SPI_nCS1 <= '0' when host_irq = '1' else 'Z';

	------------------------------------------------------------------------
	-- clocks
	------------------------------------------------------------------------
	clk_16MHz <= FPGACLK;

	u_bufg_pll_out : BUFG
		port map (
			I => PLL_OUT,
			O => clk_49_152MHz);

	-- 50 MHz RMII clock (and its inversion for the DDR registers)
	u_dcm : entity work.dcm2
		port map (
			CLKIN_IN => FPGACLK,
			RST_IN => pripll_rst,
			CLKFX_OUT => clk_50MHz,
			CLKFX180_OUT => clk_50MHz_inv,
			CLK0_OUT => open,
			LOCKED_OUT => open);

	-- 100 MHz system clock of the AES67 core
	gen_dcm100 : if G_AES67 generate
		u_dcm100 : entity work.dcm1
			port map (
				CLKIN_IN => FPGACLK,
				RST_IN => pripll_rst,
				CLKFX_OUT => clk_100MHz,
				CLK0_OUT => open,
				LOCKED_OUT => open);
	end generate;

	gen_no_dcm100 : if not G_AES67 generate
		clk_100MHz <= '0';
	end generate;

	------------------------------------------------------------------------
	-- RMII IO registers and clock forwarding
	------------------------------------------------------------------------
	u_rmii_rxd_a : entity work.aes50_rmii_rxd
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			rmii_crs_dv => aes50a_rmii_crs_dv_in,
			rmii_rxd0 => aes50a_rmii_rxd_0_in,
			rmii_rxd1 => aes50a_rmii_rxd_1_in,
			q => aes50a_rmii_rxd);

	u_rmii_txd_a : entity work.aes50_rmii_txd
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			data => aes50a_rmii_txd,
			rmii_tx_en => aes50a_rmii_tx_en_out,
			rmii_txd0 => aes50a_rmii_txd_0_out,
			rmii_txd1 => aes50a_rmii_txd_1_out);

	u_rmii_clk_a : entity work.oddr_clock
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			d0 => '1',
			d1 => '0',
			Q => aes50a_rmii_clk_out);

	u_rmii_rxd_b : entity work.aes50_rmii_rxd
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			rmii_crs_dv => aes50b_rmii_crs_dv_in,
			rmii_rxd0 => aes50b_rmii_rxd_0_in,
			rmii_rxd1 => aes50b_rmii_rxd_1_in,
			q => aes50b_rmii_rxd);

	u_rmii_txd_b : entity work.aes50_rmii_txd
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			data => aes50b_rmii_txd,
			rmii_tx_en => aes50b_rmii_tx_en_out,
			rmii_txd0 => aes50b_rmii_txd_0_out,
			rmii_txd1 => aes50b_rmii_txd_1_out);

	u_rmii_clk_b : entity work.oddr_clock
		port map (
			clk_in => clk_50MHz,
			clk_in_inv => clk_50MHz_inv,
			reset => rst,
			d0 => '1',
			d1 => '0',
			Q => aes50b_rmii_clk_out);

	------------------------------------------------------------------------
	-- network ports
	------------------------------------------------------------------------
	rmii_crs_dv <= aes50b_rmii_rxd(0) & aes50a_rmii_rxd(0);
	rmii_rxd <= aes50b_rmii_rxd(2 downto 1) & aes50a_rmii_rxd(2 downto 1);
	aes50a_rmii_txd <= rmii_txd(1 downto 0) & rmii_tx_en(0);
	aes50b_rmii_txd <= rmii_txd(3 downto 2) & rmii_tx_en(1);
	aes50a_phy_rst_n_out <= phy_rst_n(0);
	-- (the PHY of port B has no reset pin at the FPGA)

	clk_a_rx <= aes50b_clk_a_rx_in & aes50a_clk_a_rx_in;
	clk_b_rx <= aes50b_clk_b_rx_in & aes50a_clk_b_rx_in;
	aes50a_clk_a_tx_out <= clk_a_tx(0);
	aes50a_clk_b_tx_out <= clk_b_tx(0);
	aes50a_clk_a_tx_en_out <= clk_a_tx_en(0);
	aes50a_clk_b_tx_en_out <= clk_b_tx_en(0);
	aes50a_clk_a_rx_nen_out <= clk_a_rx_nen(0);
	aes50a_clk_b_rx_nen_out <= clk_b_rx_nen(0);
	aes50b_clk_a_tx_out <= clk_a_tx(1);
	aes50b_clk_b_tx_out <= clk_b_tx(1);
	aes50b_clk_a_tx_en_out <= clk_a_tx_en(1);
	aes50b_clk_b_tx_en_out <= clk_b_tx_en(1);
	aes50b_clk_a_rx_nen_out <= clk_a_rx_nen(1);
	aes50b_clk_b_rx_nen_out <= clk_b_rx_nen(1);

	------------------------------------------------------------------------
	-- console logic
	------------------------------------------------------------------------
	u_x32 : entity work.x32_common
		generic map (
			G_AES50_PORTS => G_AES50_PORTS,
			G_AES67 => G_AES67,
			G_EXT_TDM_LINES => 0,
			G_AUX_CS42438 => true,
			G_AES50_SUPPORT_44K1 => false,
			G_PLATFORM_ID => 2)
		port map (
			clk_16m_i => clk_16MHz,
			clk_50m_i => clk_50MHz,
			clk_100m_i => clk_100MHz,
			pll_rst_o => pripll_rst,
			io_rst_o => rst,
			online_o => open,
			irq_o => host_irq,
			pll_in_o => PLL_IN,
			pll_out_i => clk_49_152MHz,
			pll_ncs_o => PLL_nCS,
			pll_cclk_o => PLL_CCLK,
			pll_cdata_o => PLL_CDATA,
			clk_fs512_o => clk_24_576MHz,
			clk_fs256_o => clk_12_288MHz,
			fsync_o => tdm_fs,
			spi_ncs_i => SPI_nCS0,
			spi_clk_i => SPI_CLK,
			spi_mosi_i => SPI_MOSI,
			spi_miso_o => SPI_MISO,
			cfg_bits_o => open,
			uart3_txd_i => imx25_uart3_txd,
			uart3_rxd_o => imx25_uart3_rxd,
			da_rx_i => DA_RX,
			ad0_rx_i => AD0_RX,
			ad1_rx_i => AD1_RX,
			card_rx_i => CARD_RX,
			card_rdy_i => CARD_RDY,
			da_tx_o => DA_TX,
			ad0_tx_o => AD0_TX,
			ad1_tx_o => AD1_TX,
			card_tx_o => CARD_TX,
			ad0_data1_i => AD0_DATA1,
			ad0_data0_i => AD0_DATA0,
			ad1_data1_i => AD1_DATA1,
			ad1_data0_i => AD1_DATA0,
			card_in3_i => CARD_IN3,
			card_in2_i => CARD_IN2,
			card_in1_i => CARD_IN1,
			card_in0_i => CARD_IN0,
			aux_ad_i => AUX_AD,
			dsp_dout_i => dsp_dout,
			dsp_doutaux_i => DSP_DOUTAUX,
			da_data1_o => DA_DATA1,
			da_data0_o => DA_DATA0,
			card_out_o => card_out,
			aux_da_o => AUX_DA,
			dsp_din_o => dsp_din,
			dsp_dinaux_o => DSP_DINAUX,
			ext_tdm_i => open,
			ext_tdm_o => open,
			p16_a_txp_o => P16_A_TXP,
			p16_a_txm_o => P16_A_TXM,
			p16_b_txp_o => P16_B_TXP,
			p16_b_txm_o => P16_B_TXM,
			aux_cclk_o => AUX_CCLK,
			aux_cdata_o => AUX_CDATA,
			aux_nrst_o => AUX_nRST,
			aux_ncs_o => AUX_nCS,
			aux_ad_ncs_o => open,
			aux_da_ncs_o => open,
			conv_nrst_o => conv_nrst,
			rmii_crs_dv_i => rmii_crs_dv,
			rmii_rxd_i => rmii_rxd,
			rmii_tx_en_o => rmii_tx_en,
			rmii_txd_o => rmii_txd,
			phy_rst_n_o => phy_rst_n,
			aes50_clk_a_rx_i => clk_a_rx,
			aes50_clk_a_tx_o => clk_a_tx,
			aes50_clk_a_tx_en_o => clk_a_tx_en,
			aes50_clk_a_rx_nen_o => clk_a_rx_nen,
			aes50_clk_b_rx_i => clk_b_rx,
			aes50_clk_b_tx_o => clk_b_tx,
			aes50_clk_b_tx_en_o => clk_b_tx_en,
			aes50_clk_b_rx_nen_o => clk_b_rx_nen,
			uart4_txd_i => imx25_uart4_txd,
			uart4_rxd_o => imx25_uart4_rxd);

	-- on this board the DSP lines 11 and 12 are called POUT0 / POUT1
	dsp_dout <= DSP_POUT1 & DSP_POUT0 & DSP_DOUT1 & DSP_DOUT0;
	DSP_DIN0 <= dsp_din(0);
	DSP_DIN1 <= dsp_din(1);
	DSP_DIN2 <= dsp_din(2);
	DSP_DIN3 <= dsp_din(3);
	CARD_OUT0 <= card_out(0);
	CARD_OUT1 <= card_out(1);
	CARD_OUT2 <= card_out(2);
	CARD_OUT3 <= card_out(3);

	------------------------------------------------------------------------
	-- audio clocks and resets of the boards
	------------------------------------------------------------------------
	AD0_MCLK <= clk_12_288MHz;
	AD0_BCLK <= clk_12_288MHz;
	AD0_FSYNC <= tdm_fs;
	AD1_MCLK <= clk_12_288MHz;
	AD1_BCLK <= clk_12_288MHz;
	AD1_FSYNC <= tdm_fs;
	DA_MCLK <= clk_12_288MHz;
	DA_BCLK <= clk_12_288MHz;
	DA_FSYNC <= tdm_fs;
	AUX_MCLK <= clk_12_288MHz;
	AUX_SCLK <= clk_12_288MHz;
	AUX_FSYNC <= tdm_fs;
	CARD_BCLK <= clk_12_288MHz;
	CARD_FSYNC <= tdm_fs;
	D_CLK <= clk_12_288MHz;
	D_FS <= tdm_fs;
	D_CLK2 <= clk_12_288MHz;	-- as before on this board (the ECP5 board gets 24.576 MHz)
	D_FS2 <= tdm_fs;
	DA_nRESET <= conv_nrst;
	AD_nRESET <= conv_nrst;
end architecture rtl;
