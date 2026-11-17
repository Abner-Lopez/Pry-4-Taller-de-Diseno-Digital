`timescale 1ns / 1ps

// Este modulo se usa para poder agregar el PWM al Block Design con
// Add Module. Se hizo este en Verilog que solo conecta
// los puertos de pwm_axi. Aqui no hay logica, todo el PWM esta en
// pwm_axi.sv y pwm_core.sv.
// Los atributos X_INTERFACE son para que Vivado reconozca las senales
// S_AXI_* como una interfaz AXI4-Lite, junto con su reloj y su reset
// (activo en bajo).

module pwm_bd (
    output wire gate_a_h_o,
    output wire gate_a_l_o,
    output wire gate_b_h_o,
    output wire gate_b_l_o,
    output wire pwm_trigger_o,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET S_AXI_ARESETN" *)
    input  wire        S_AXI_ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        S_AXI_ARESETN,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 4" *)
    input  wire [3:0]  S_AXI_AWADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]  S_AXI_AWPROT,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        S_AXI_AWVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire        S_AXI_AWREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] S_AXI_WDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  S_AXI_WSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        S_AXI_WVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire        S_AXI_WREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  S_AXI_BRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire        S_AXI_BVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        S_AXI_BREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [3:0]  S_AXI_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]  S_AXI_ARPROT,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        S_AXI_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire        S_AXI_ARREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] S_AXI_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  S_AXI_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire        S_AXI_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        S_AXI_RREADY
);

    pwm_axi u_pwm_axi (
        .gate_a_h_o    (gate_a_h_o),
        .gate_a_l_o    (gate_a_l_o),
        .gate_b_h_o    (gate_b_h_o),
        .gate_b_l_o    (gate_b_l_o),
        .pwm_trigger_o (pwm_trigger_o),
        .S_AXI_ACLK    (S_AXI_ACLK),
        .S_AXI_ARESETN (S_AXI_ARESETN),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY)
    );

endmodule
