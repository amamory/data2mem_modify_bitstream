# Processor-based designs have internal BRAMs that must be loaded with theirs initial contents.
# This script lists all its BRAMs to get its location (i.e. cell property LOC) into the FPGA.
# Processor-based designs have internal BRAMs that must be loaded with theirs initial contents.
# This script identifies the BRAMs of each memory block to create a BMM file.
# This BMM is required to run data2mem, which allows to update the bitstream with the memory content.
#
# Author: Alexandre Amory, November 2020
# Source: based on https://forums.xilinx.com/t5/Vivado-TCL-Community/Need-TCL-script-to-generate-data2mem-bmm-file-from-NON-EDK-based/td-p/420189
# Other sources:
# - https://www.xilinx.com/Attachment/data2mem_standalone.pdf
# - https://china.xilinx.com/support/answers/59259.html
# - Xilinx Data2MEM User Guide (UG658)
# - https://www.xilinx.com/support/documentation/sw_manuals/xilinx14_5/data2mem.pdf
#
# TODO:
# - read the BRAM property 'bmm_info_memory_device	[31:16][0:2047]' to get a accurate BRAM info
#   making a more robust script
# - use also updatemem to update the bitstream
#    - https://github.com/yzt000000/scr1_fpga/blob/master/fpga-sdk-prj-master/scripts/xilinx/mem_update.tcl
#    - https://www.xilinx.com/support/answers/63041.html
#    - chapter 7 in https://www.xilinx.com/support/documentation/sw_manuals/xilinx2017_3/ug898-vivado-embedded-design.pdf


#if { ![info exists env(VIVADO_DESIGN_NAME)] } {
#    puts "ERROR: Please set the environment variable VIVADO_DESIGN_NAME before running the script"
#    return
#}
#set design_name $::env(VIVADO_DESIGN_NAME)
#puts "Using design name: ${design_name}"
#
#if { ![info exists env(VIVADO_TOP_NAME)] } {
#    puts "WARNING: No top design defined. Using the default top name ${design_name}_wrapper"
#    set top_name ${design_name}_wrapper
#} else {
#  set top_name $::env(VIVADO_TOP_NAME)
#  puts "Using top name: ${top_name}"
#}
#
namespace import ::tcl::mathfunc::*


##########################################
#
#    THESE VARIABLES MUST BE CHANGED 
#     ACCORDING TO THE DESIGN !!!!!
#
##########################################
set design_name bit_modif
set top_name bit_modif_wrapper
set data_width 32
# its depth is 8192
set data_depth [expr pow(2, 13)]
# number of independent memory blocks
set num_mem 2

# open the design and the name of the implementation where the bitstream have been created
# assuminig the implementation 'impl_1'. Adapt it otherwise.
open_project ./vivado/${design_name}/${design_name}.xpr
open_run impl_1 -name impl_1

set myInsts [get_cells -hier -filter {PRIMITIVE_TYPE =~ BMEM.*.*}]
puts "Raw Number for Instances: [llength $myInsts]"

# Open the BMM file to put describe the memory organization.
set fp [open mem_dump.bmm w+]

# for each memory block, find its BRAMs
for { set mem_cnt 0}  {$mem_cnt < $num_mem} {incr mem_cnt} {
    puts "generating the BMM for memory # $mem_cnt"
    # the name of the memory block defined in the block diagram
    set mem_label "blk_mem_gen_$mem_cnt"
    set bmmList {}; # make it empty in case you were running it interactively

    # this first loop separates only the BRAMs of this memory block
    set bram_List {};
    foreach memInst $myInsts {
        # First occurrence of $mem_label in $memInst
        if {[string first $mem_label $memInst] != -1} {
            lappend bram_List $memInst
        }
    }
    # this is used to set the data width of each BRAM of this memory block
    set bram_width [expr $data_width / [llength $bram_List]]
    #puts "BRAM width ${bram_width}"
    set cnt 0
    foreach memInst $bram_List {
        # this is the property we need
        #LOC                             site     false      RAMB36_X6Y39
        set loc [get_property LOC $memInst]
        #report_property $memInst LOC
        # for BMM the location is just the XY location (e.g. X6Y39) 
        # so remove the extra data, e.g. RAMB36_
        #set loc [string trimleft $loc RAMB36_]
        # this splits the string using the _ as a separator and take the index [1] of the list, discarding the 'RAMB36_' part
        set loc [lrange [split $loc _] 1 1]
        # find the bus index, this is specific to our design
        set busindex [string range $memInst [string first \[ $memInst] [string last \] $memInst]]
        # build a list in a format which is close to the output we need
        set left_bit [expr ($cnt*$bram_width)+$bram_width-1]
        set right_bit [expr $cnt*$bram_width]
        set x "$memInst $busindex [$left_bit:$right_bit] LOC=$loc"
        lappend bmmList $x
        #puts "set_property LOC $loc \[get_cells $memInst\]"  # for XDC locking
        #DEBUG: puts "Locating Instance: $memInst to $x"
        set cnt [expr $cnt + 1]
    }

    # debug message:
    puts "Parsed Locations Number of Intances: [llength $bmmList]"
    #DEBUG: foreach memInst $bmmList { puts "Stored: $memInst" }
    #foreach memInst $bmmList { puts "Stored: $memInst" }

    # Remove duplicates, although there shouldn't be any
    set bmmUniqueList [lsort -unique $bmmList]

    # calculate to top addr based on its size
    set top_addr_int [expr $data_depth -1]
    set top_addr  [format "%X" [int ${top_addr_int}]] 

    #
    # The format of the BMM file is specificed in the data2mem manual and
    # this is what just works for us so if you want something different
    # then you need to understand how this file behaves.
    # Start the A Memories:

    # Assuming the starting address of the elf file is 0x00000000. If it is not the case,
    # then this line must match the elf starting address
    puts $fp "ADDRESS_SPACE memory_$mem_cnt COMBINED \[0x00000000:0x00000${top_addr}\]"
    puts $fp "  ADDRESS_RANGE RAMB32"
    puts $fp "     BUS_BLOCK"
    foreach printList [lsort -dictionary $bmmUniqueList] {
        #DEBUG: puts "Processing $printList"
        #puts "Processing $printList"
        puts $fp "       $printList;"
    }
    puts $fp "     END_BUS_BLOCK;"
    puts $fp "  END_ADDRESS_RANGE;"
    puts $fp "END_ADDRESS_SPACE;"
    puts $fp ""
}
close $fp

# Check if necessary files are present
if {![file exists ./mem_dump.bmm]} {
    error "ERROR! BMM-file $bit_file is not found."
}
if {![file exists ./src/processor-based/image.elf]} {
    error "ERROR! Elf-file $mem_file is not found."
}
if {![file exists ./vivado/bit_modif/bit_modif.runs/impl_1/bit_modif_wrapper.bit]} {
    error "ERROR! Bit-file $mem_file is not found."
}

# insert the elf file into the bitstream
# TODO improve the error recover for executing data2mem
# example in https://github.com/alishbakanwal/Xilinx_Vivado_Lab_Tools/blob/master/Xilinx_Vivado_Lab_Tools/scripts/updatemem/main.tcl
exec data2mem -bm ./mem_dump.bmm -bd ./src/processor-based/image.elf -bt ./vivado/bit_modif/bit_modif.runs/impl_1/bit_modif_wrapper.bit -o b new.bit

# cleanup
unset myInsts
unset bmmList
unset loc
unset busindex 
unset x 
unset bmmUniqueList
unset fp 

# end of file
