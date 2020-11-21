# Processor-based designs have internal BRAMs that must be loaded with theirs initial contents.
# This script lists all its BRAMs to get its location (i.e. cell property LOC) into the FPGA.
# Processor-based designs have internal BRAMs that must be loaded with theirs initial contents.
# This script identifies the BRAMs of each memory bank to create a BMM file.
# This BMM is required to run data2mem, which allows to update the bitstream with the memory content.
#
# Author: Alexandre Amory, November 2020
# Source: based on https://forums.xilinx.com/t5/Vivado-TCL-Community/Need-TCL-script-to-generate-data2mem-bmm-file-from-NON-EDK-based/td-p/420189
# Other sources:
# - https://www.xilinx.com/Attachment/data2mem_standalone.pdf
# - https://china.xilinx.com/support/answers/59259.html
# - Xilinx Data2MEM User Guide (UG658)
# - https://www.xilinx.com/support/documentation/sw_manuals/xilinx14_5/data2mem.pdf


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

set design_name bit_modif
set top_name bit_modif_wrapper
set data_width 32
# its depth is 8192
set data_depth [expr pow(2, 12)]

# number of independent memort banks
set num_mem 2

#puts ${data_width}
#puts ${data_depth}
#puts ${top_addr}

open_project ./vivado/${design_name}/${design_name}.xpr
open_run impl_1 -name impl_1

set myInsts [get_cells -hier -filter {PRIMITIVE_TYPE =~ BMEM.*.*}]
puts "Raw Number for Instances: [llength $myInsts]"

# Open a file to put the data into.
set fp [open mem_dump.bmm w+]

# for each memory bank, find its BRAMs
for { set mem_cnt 0}  {$mem_cnt < $num_mem} {incr mem_cnt} {
    puts "generating the BMM for memory # $mem_cnt"
    # the name of the memory block defined in the block diagram
    set mem_label "blk_mem_gen_$mem_cnt"
    set bmmList {}; # make it empty incase you were running it interactively

    # this first loop separates only the BRAMs of this memory bank
    set bram_List {};
    foreach memInst $myInsts {
        # First occurrence of $mem_label in $memInst
        if {[string first $mem_label $memInst] != -1} {
            lappend bram_List $memInst
        }
    }
    # this is used to set the datawidth of each BRAM of this memory bank
    set bram_width [expr $data_width / [llength $bram_List]]
    #puts "BRAM width ${bram_width}"
    set cnt 0
    foreach memInst $bram_List {
        # this is the property we need
        #LOC                             site     false      RAMB36_X6Y39
        
        #report_property $memInst LOC
        set loc [get_property LOC $memInst]
        # for BMM the location is just the XY location so remove the extra data
        set loc [string trimleft $loc RAMB36_]
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

    # a hack to fix the size of the RAM blocks. blk_mem_gen_0 * 2 == blk_mem_gen_1
    set top_addr_int [expr ($data_depth * ($mem_cnt+1)) -1]
    set top_addr  [format "%X" [int ${top_addr_int}]] 

    #
    # The format of the BMM file is specificed in the data2mem manual and
    # this is what just works for us so if you want something different
    # then you need to understand how this file behaves.
    # Start the A Memories:

    # Assuming the starting address of the elf file is 0x00000000. If it is not the case,
    # then this line must match the elf starting address
    puts $fp "ADDRESS_SPACE memory_$mem_cnt COMBINED \[0x00000000:0x00000${top_addr}\]"
    puts $fp "  ADDRESS_RANGE RAMB32\n     BUS_BLOCK"
    foreach printList [lsort -dictionary $bmmUniqueList] {
        #DEBUG: puts "Processing $printList"
        puts "Processing $printList"
        puts $fp "       $printList;"
    }
    puts $fp "     END_BUS_BLOCK;"
    puts $fp "  END_ADDRESS_RANGE;"
    puts $fp "END_ADDRESS_SPACE;"
    puts $fp ""
}
close $fp

# insert the elf file into the bitstream
exec data2mem -bm mem_dump.bmm -bd image.elf -bt ./vivado/bit_modif/bit_modif.runs/impl_1/bit_modif_wrapper.bit -o b new.bit

# cleanup
unset myInsts
unset bmmList
unset loc
unset busindex 
unset x 
unset bmmUniqueList
unset fp 

# end of file
