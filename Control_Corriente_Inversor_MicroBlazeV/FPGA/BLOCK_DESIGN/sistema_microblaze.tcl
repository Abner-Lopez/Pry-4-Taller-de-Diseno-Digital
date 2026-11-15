
################################################################
# This is a generated script based on design: sistema_microblaze
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source sistema_microblaze_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# pwm_bd

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7a100tcsg324-1
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name sistema_microblaze

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:microblaze_riscv:1.0\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:axi_intc:4.1\
xilinx.com:inline_hdl:ilconcat:1.0\
xilinx.com:ip:mdm_riscv:1.0\
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:axi_uartlite:2.0\
xilinx.com:ip:axi_timer:2.0\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:xadc_wiz:3.3\
xilinx.com:ip:lmb_v10:3.0\
xilinx.com:ip:lmb_bram_if_cntlr:4.0\
xilinx.com:ip:blk_mem_gen:8.4\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
pwm_bd\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: microblaze_riscv_0_local_memory
proc create_hier_cell_microblaze_riscv_0_local_memory { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_microblaze_riscv_0_local_memory() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB

  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB


  # Create pins
  create_bd_pin -dir I -type clk LMB_Clk
  create_bd_pin -dir I -type rst SYS_Rst

  # Create instance: dlmb_v10, and set properties
  set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 dlmb_v10 ]

  # Create instance: ilmb_v10, and set properties
  set ilmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 ilmb_v10 ]

  # Create instance: dlmb_bram_if_cntlr, and set properties
  set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 dlmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $dlmb_bram_if_cntlr


  # Create instance: ilmb_bram_if_cntlr, and set properties
  set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 ilmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $ilmb_bram_if_cntlr


  # Create instance: lmb_bram, and set properties
  set lmb_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 lmb_bram ]
  set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.use_bram_block {BRAM_Controller} \
  ] $lmb_bram


  # Create interface connections
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb [get_bd_intf_pins dlmb_v10/LMB_M] [get_bd_intf_pins DLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_bus [get_bd_intf_pins dlmb_v10/LMB_Sl_0] [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_cntlr [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb [get_bd_intf_pins ilmb_v10/LMB_M] [get_bd_intf_pins ILMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_bus [get_bd_intf_pins ilmb_v10/LMB_Sl_0] [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_cntlr [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

  # Create port connections
  connect_bd_net -net SYS_Rst_1  [get_bd_pins SYS_Rst] \
  [get_bd_pins dlmb_v10/SYS_Rst] \
  [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst] \
  [get_bd_pins ilmb_v10/SYS_Rst] \
  [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst]
  connect_bd_net -net microblaze_riscv_0_Clk  [get_bd_pins LMB_Clk] \
  [get_bd_pins dlmb_v10/LMB_Clk] \
  [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] \
  [get_bd_pins ilmb_v10/LMB_Clk] \
  [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set uart [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart ]

  set leds [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 leds ]

  set switches [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 switches ]

  set buttons [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 buttons ]

  set prueba [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 prueba ]

  set vaux3 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vaux3 ]


  # Create ports
  set clk100_i [ create_bd_port -dir I -type clk -freq_hz 100000000 clk100_i ]
  set cpu_resetn_i [ create_bd_port -dir I -type rst cpu_resetn_i ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $cpu_resetn_i
  set gate_a_h_o [ create_bd_port -dir O gate_a_h_o ]
  set gate_a_l_o [ create_bd_port -dir O gate_a_l_o ]
  set gate_b_h_o [ create_bd_port -dir O gate_b_h_o ]
  set gate_b_l_o [ create_bd_port -dir O gate_b_l_o ]
  set pwm_trigger_o [ create_bd_port -dir O pwm_trigger_o ]

  # Create instance: microblaze_riscv_0, and set properties
  set microblaze_riscv_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze_riscv:1.0 microblaze_riscv_0 ]
  set_property -dict [list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_USE_FPU {1} \
    CONFIG.C_USE_MULDIV {1} \
  ] $microblaze_riscv_0


  # Create instance: microblaze_riscv_0_local_memory
  create_hier_cell_microblaze_riscv_0_local_memory [current_bd_instance .] microblaze_riscv_0_local_memory

  # Create instance: microblaze_riscv_0_axi_periph, and set properties
  set microblaze_riscv_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 microblaze_riscv_0_axi_periph ]
  set_property -dict [list \
    CONFIG.NUM_MI {7} \
    CONFIG.NUM_SI {1} \
  ] $microblaze_riscv_0_axi_periph


  # Create instance: microblaze_riscv_0_axi_intc, and set properties
  set microblaze_riscv_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 microblaze_riscv_0_axi_intc ]
  set_property CONFIG.C_HAS_FAST {1} $microblaze_riscv_0_axi_intc


  # Create instance: microblaze_riscv_0_xlconcat, and set properties
  set microblaze_riscv_0_xlconcat [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 microblaze_riscv_0_xlconcat ]
  set_property CONFIG.NUM_PORTS {1} $microblaze_riscv_0_xlconcat


  # Create instance: mdm_1, and set properties
  set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm_riscv:1.0 mdm_1 ]

  # Create instance: clk_wiz_1, and set properties
  set clk_wiz_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1 ]
  set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
  ] $clk_wiz_1


  # Create instance: rst_clk_wiz_1_100M, and set properties
  set rst_clk_wiz_1_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M ]

  # Create instance: axi_uartlite_0, and set properties
  set axi_uartlite_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0 ]
  set_property -dict [list \
    CONFIG.C_BAUDRATE {115200} \
    CONFIG.C_DATA_BITS {8} \
    CONFIG.C_USE_PARITY {0} \
  ] $axi_uartlite_0


  # Create instance: axi_timer_0, and set properties
  set axi_timer_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer:2.0 axi_timer_0 ]

  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {16} \
    CONFIG.C_GPIO_WIDTH {16} \
    CONFIG.C_IS_DUAL {1} \
  ] $axi_gpio_0


  # Create instance: axi_gpio_1, and set properties
  set axi_gpio_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_GPIO_WIDTH {5} \
    CONFIG.C_IS_DUAL {1} \
  ] $axi_gpio_1


  # Create instance: pwm_0, and set properties
  set block_name pwm_bd
  set block_cell_name pwm_0
  if { [catch {set pwm_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $pwm_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: xadc_wiz_0, and set properties
  set xadc_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xadc_wiz:3.3 xadc_wiz_0 ]
  set_property -dict [list \
    CONFIG.DCLK_FREQUENCY {100} \
    CONFIG.ENABLE_CONVST {true} \
    CONFIG.INTERFACE_SELECTION {Enable_AXI} \
    CONFIG.OT_ALARM {false} \
    CONFIG.SINGLE_CHANNEL_SELECTION {VAUXP3_VAUXN3} \
    CONFIG.TIMING_MODE {Event} \
    CONFIG.USER_TEMP_ALARM {false} \
    CONFIG.VCCAUX_ALARM {false} \
    CONFIG.VCCINT_ALARM {false} \
    CONFIG.XADC_STARUP_SELECTION {single_channel} \
  ] $xadc_wiz_0


  # Create interface connections
  connect_bd_intf_net -intf_net axi_gpio_0_GPIO [get_bd_intf_ports leds] [get_bd_intf_pins axi_gpio_0/GPIO]
  connect_bd_intf_net -intf_net axi_gpio_0_GPIO2 [get_bd_intf_ports switches] [get_bd_intf_pins axi_gpio_0/GPIO2]
  connect_bd_intf_net -intf_net axi_gpio_1_GPIO [get_bd_intf_ports buttons] [get_bd_intf_pins axi_gpio_1/GPIO]
  connect_bd_intf_net -intf_net axi_gpio_1_GPIO2 [get_bd_intf_ports prueba] [get_bd_intf_pins axi_gpio_1/GPIO2]
  connect_bd_intf_net -intf_net axi_uartlite_0_UART [get_bd_intf_ports uart] [get_bd_intf_pins axi_uartlite_0/UART]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_dp [get_bd_intf_pins microblaze_riscv_0_axi_periph/S00_AXI] [get_bd_intf_pins microblaze_riscv_0/M_AXI_DP]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M01_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M01_AXI] [get_bd_intf_pins axi_uartlite_0/S_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M02_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M02_AXI] [get_bd_intf_pins axi_timer_0/S_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M03_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M03_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M04_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M04_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M05_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M05_AXI] [get_bd_intf_pins pwm_0/S_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M06_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M06_AXI] [get_bd_intf_pins xadc_wiz_0/s_axi_lite]
  connect_bd_intf_net -intf_net microblaze_riscv_0_debug [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_riscv_0/DEBUG]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_1 [get_bd_intf_pins microblaze_riscv_0/DLMB] [get_bd_intf_pins microblaze_riscv_0_local_memory/DLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_1 [get_bd_intf_pins microblaze_riscv_0/ILMB] [get_bd_intf_pins microblaze_riscv_0_local_memory/ILMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_intc_axi [get_bd_intf_pins microblaze_riscv_0_axi_periph/M00_AXI] [get_bd_intf_pins microblaze_riscv_0_axi_intc/s_axi]
  connect_bd_intf_net -intf_net microblaze_riscv_0_interrupt [get_bd_intf_pins microblaze_riscv_0_axi_intc/interrupt] [get_bd_intf_pins microblaze_riscv_0/INTERRUPT]
  connect_bd_intf_net -intf_net vaux3_1 [get_bd_intf_ports vaux3] [get_bd_intf_pins xadc_wiz_0/Vaux3]

  # Create port connections
  connect_bd_net -net axi_timer_0_interrupt  [get_bd_pins axi_timer_0/interrupt] \
  [get_bd_pins microblaze_riscv_0_xlconcat/In0]
  connect_bd_net -net clk100_i_1  [get_bd_ports clk100_i] \
  [get_bd_pins clk_wiz_1/clk_in1]
  connect_bd_net -net clk_wiz_1_locked  [get_bd_pins clk_wiz_1/locked] \
  [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]
  connect_bd_net -net cpu_resetn_i_1  [get_bd_ports cpu_resetn_i] \
  [get_bd_pins clk_wiz_1/resetn] \
  [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in]
  connect_bd_net -net mdm_1_debug_sys_rst  [get_bd_pins mdm_1/Debug_SYS_Rst] \
  [get_bd_pins rst_clk_wiz_1_100M/mb_debug_sys_rst]
  connect_bd_net -net microblaze_riscv_0_Clk  [get_bd_pins clk_wiz_1/clk_out1] \
  [get_bd_pins microblaze_riscv_0/Clk] \
  [get_bd_pins microblaze_riscv_0_axi_periph/aclk] \
  [get_bd_pins microblaze_riscv_0_axi_intc/s_axi_aclk] \
  [get_bd_pins microblaze_riscv_0_axi_intc/processor_clk] \
  [get_bd_pins microblaze_riscv_0_local_memory/LMB_Clk] \
  [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk] \
  [get_bd_pins axi_uartlite_0/s_axi_aclk] \
  [get_bd_pins axi_timer_0/s_axi_aclk] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] \
  [get_bd_pins axi_gpio_1/s_axi_aclk] \
  [get_bd_pins pwm_0/S_AXI_ACLK] \
  [get_bd_pins xadc_wiz_0/s_axi_aclk]
  connect_bd_net -net microblaze_riscv_0_intr  [get_bd_pins microblaze_riscv_0_xlconcat/dout] \
  [get_bd_pins microblaze_riscv_0_axi_intc/intr]
  connect_bd_net -net pwm_0_gate_a_h_o  [get_bd_pins pwm_0/gate_a_h_o] \
  [get_bd_ports gate_a_h_o]
  connect_bd_net -net pwm_0_gate_a_l_o  [get_bd_pins pwm_0/gate_a_l_o] \
  [get_bd_ports gate_a_l_o]
  connect_bd_net -net pwm_0_gate_b_h_o  [get_bd_pins pwm_0/gate_b_h_o] \
  [get_bd_ports gate_b_h_o]
  connect_bd_net -net pwm_0_gate_b_l_o  [get_bd_pins pwm_0/gate_b_l_o] \
  [get_bd_ports gate_b_l_o]
  connect_bd_net -net pwm_0_pwm_trigger_o  [get_bd_pins pwm_0/pwm_trigger_o] \
  [get_bd_ports pwm_trigger_o] \
  [get_bd_pins xadc_wiz_0/convst_in]
  connect_bd_net -net rst_clk_wiz_1_100M_bus_struct_reset  [get_bd_pins rst_clk_wiz_1_100M/bus_struct_reset] \
  [get_bd_pins microblaze_riscv_0_local_memory/SYS_Rst]
  connect_bd_net -net rst_clk_wiz_1_100M_mb_reset  [get_bd_pins rst_clk_wiz_1_100M/mb_reset] \
  [get_bd_pins microblaze_riscv_0/Reset] \
  [get_bd_pins microblaze_riscv_0_axi_intc/processor_rst]
  connect_bd_net -net rst_clk_wiz_1_100M_peripheral_aresetn  [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn] \
  [get_bd_pins microblaze_riscv_0_axi_periph/aresetn] \
  [get_bd_pins microblaze_riscv_0_axi_intc/s_axi_aresetn] \
  [get_bd_pins axi_uartlite_0/s_axi_aresetn] \
  [get_bd_pins axi_timer_0/s_axi_aresetn] \
  [get_bd_pins axi_gpio_0/s_axi_aresetn] \
  [get_bd_pins axi_gpio_1/s_axi_aresetn] \
  [get_bd_pins pwm_0/S_AXI_ARESETN] \
  [get_bd_pins xadc_wiz_0/s_axi_aresetn]

  # Create address segments
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x40010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs axi_gpio_1/S_AXI/Reg] -force
  assign_bd_address -offset 0x41C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs axi_timer_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x40600000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs axi_uartlite_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs microblaze_riscv_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs microblaze_riscv_0_axi_intc/S_AXI/Reg] -force
  assign_bd_address -offset 0x00010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs pwm_0/S_AXI/reg0] -force
  assign_bd_address -offset 0x44A00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs xadc_wiz_0/s_axi_lite/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Instruction] [get_bd_addr_segs microblaze_riscv_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


