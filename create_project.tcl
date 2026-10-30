# Recreate the Vivado project from the sources in this repo.
# The project is built in ./build and points at the files in uart_uvm.srcs
# (nothing is copied), so edits made in Vivado land in the tracked sources.
#
#   Batch:       vivado -mode batch -source create_project.tcl
#   Tcl console: cd <repo>; source create_project.tcl

set root [file normalize [file dirname [info script]]]
set proj uart_uvm

create_project $proj $root/build -part xc7vx485tffg1157-1 -force
set_property target_language Verilog [current_project]

# Design sources
add_files -norecurse -fileset sources_1 [glob $root/uart_uvm.srcs/sources_1/new/*.sv]
set_property top uart_top [get_filesets sources_1]

# The interface and UVM package are testbench-only: keep them out of synthesis
foreach f {uart_if.sv uart_pkg.sv} {
  set_property used_in_synthesis      false [get_files $f]
  set_property used_in_implementation false [get_files $f]
}

# Testbench
add_files -norecurse -fileset sim_1 [glob $root/uart_uvm.srcs/sim_1/new/*.sv]
set_property top     tb_top         [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name xsim.compile.xvlog.more_options  -value {-L uvm} -objects [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options -value {-L uvm} -objects [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value 5ms -objects [get_filesets sim_1]

puts "Project created: $root/build/$proj.xpr"
