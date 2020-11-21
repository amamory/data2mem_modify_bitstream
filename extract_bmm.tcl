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

namespace import ::tcl::mathfunc::*

if { ![info exists env(VIVADO_DESIGN_NAME)] } {
   puts "ERROR: Please set the environment variable VIVADO_DESIGN_NAME before running the script"
   return
}
set design_name $::env(VIVADO_DESIGN_NAME)
puts "Using design name: ${design_name}"

if { ![info exists env(VIVADO_TOP_NAME)] } {
   puts "WARNING: No top design defined. Using the default top name ${design_name}_wrapper"
   set top_name ${design_name}_wrapper
} else {
 set top_name $::env(VIVADO_TOP_NAME)
 puts "Using top name: ${top_name}"
}

# An issue when there are more than 10 BRAMs is that the labels are recieved in 
# alphabetical order. For example, it would return:
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_0
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_1
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_10
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_11
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_12
#...
# Instead of:
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_0
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_1
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_2
#...
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_10
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_11
#orca_zed_i/orca_top_0/U0/proc[1].orca_tile/proc_tile_mem_binding/ram_reg_12
#
# The order is relevant, otherwise the bits will be inverted into the BRAMs.
#
# One solution is to split the list according to the label lengths, 
# which is equivalent to split the lists by units, tens, hundreds, etc
# Once they are split, then sort each list, and finally, combine the lists
# again into a single list.
# The following procedure does this 'hack' to fix the order of the labels.
# 
proc Reorder_Labels {labelList} {
    set sortedList {}

    # get the shortest string in the labelList (units)
    set shortest 10000
    foreach label $labelList {
        if {[string length $label] < $shortest} {
            set shortest [string length $label]
        }
    }

    # lists to separe the labels by lenght
    set unitsList {}
    set tensList {}
    set hundsList {}

    # I dont expect to have more than 999 BRAM in a single RAM block.
    # So, 3 digits is ok
    foreach label $labelList {
        set labelLen [string length $label]
        if {$labelLen == $shortest} {
            lappend unitsList $label
        } elseif {$labelLen == [expr $shortest + 1]} {
            lappend tensList $label
        } elseif {$labelLen == [expr $shortest + 2]} {
            lappend hundsList $label
        } else {
            error "ERROR: that's quite a memory !!!!"
        }
    }

    # Now that the list is separated into 3 lists, 
    # it is necessary to sort these lists and combine them into a single list
    set unitsList [lsort $unitsList]
    set tensList [lsort $tensList]
    set hundsList [lsort $hundsList]
    set sortedList [concat $unitsList $tensList $hundsList]

    return $sortedList
}

##########################################
#
#    THESE VARIABLES MUST BE CHANGED 
#     ACCORDING TO THE DESIGN !!!!!
#
##########################################
#set design_name bit_modif
#set top_name bit_modif_wrapper
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

# Open the BMM file to describe the memory organization.
set fp [open mem_dump.bmm w+]

# for each memory block, find its BRAMs
for { set mem_cnt 0}  {$mem_cnt < $num_mem} {incr mem_cnt} {
    puts "generating the BMM for memory # $mem_cnt"
    # all BRAMs found under this label belong to the same memory block
    ###################################
    #
    #    THIS LABEL MUST BE CHANGED 
    #   ACCORDING TO THE DESIGN !!!!!
    #
    ###################################
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
    # reorder the list of labels
    set bram_List [Reorder_Labels $bram_List]
    # this is used to set the data width of each BRAM of this memory block
    set bram_width [expr $data_width / [llength $bram_List]]
    #puts "BRAM width ${bram_width} - $data_width - [llength $bram_List]"
    if {[expr $data_width % [llength $bram_List]] != 0} {
        error "ERROR in data witdth ${data_width} and number of BRAMs [llength $bram_List]"
    }
    if {$bram_width < 1} {
        error "ERROR in BRAM witdth ${bram_width}. Expecting at least 1 bit."
    }
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
    error "ERROR! BMM-file ./mem_dump.bmm is not found."
}
if {![file exists ./src/processor-based/image.elf]} {
    error "ERROR! Elf-file ./src/processor-based/image.elf is not found."
}
if {![file exists ./vivado/${design_name}/${design_name}.runs/impl_1/${top_name}.bit]} {
    error "ERROR! Bit-file ./vivado/${design_name}/${design_name}.runs/impl_1/${top_name}.bit is not found."
}

# insert the elf file into the bitstream
# TODO improve the error recover for executing data2mem
# example in https://github.com/alishbakanwal/Xilinx_Vivado_Lab_Tools/blob/master/Xilinx_Vivado_Lab_Tools/scripts/updatemem/main.tcl
exec data2mem -bm ./mem_dump.bmm -bd ./src/processor-based/image.elf -bt ./vivado/${design_name}/${design_name}.runs/impl_1/${top_name}.bit -o b new.bit

# cleanup
unset myInsts
unset bmmList
unset loc
unset busindex 
unset x 
unset bmmUniqueList
unset fp 

# end of file
