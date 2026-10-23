#!./oocd.sh

init
scan_chain

# The name and bit width of each field in the captured data
# starting at the least-significant bit

set capture_fields {
	{ clkena 1 }
	{ cpustate 2 }
	{ sel_chip 1 }
	{ sel_kick 1 }
	{ sel_fast24 1 }
	{ sel_fast32 1 }
	{ pad 23 }
	{ rle 1 }
}

# Enumerate user IR codes, starting at 0

set ::jcapture::usercodes {
	resetcounters start stop fetch fetchtotal externalreset
}


puts "Setting TAP, capture fields and length"

set loc [file dirname [file normalize [info script]]]
source ${loc}/../rtl/jcapture2/tcl/jcapture.tcl
::jcapture::setup target.tap $capture_fields 0x1010

::jcapture::usercmd resetcounters

::jcapture::settrigger cpustate 0x00
::jcapture::setleadin 3
# Start recording
::jcapture::capture
::jcapture::usercmd start
puts "Monitoring CPU accesses"
after 20
::jcapture::usercmd stop
::jcapture::usercmd fetch
set categories {"Chip RAM" "Kickstart" "24-bit Fast RAM" "32-bit Fast RAM"}

proc scanpretty { } {
	set result [::jcapture::vdrscan 32 0]
	if {$result == "00000000"} {
		set result "    -   "
	}
	return $result
}

foreach category $categories {
	puts ""
	puts "$category"
	puts "Cycles:\tInst Fetch:\tInternal:\tData read:\tData write:"
	for {set i 1} {$i < 17} {incr i} {
		puts "$i\t[scanpretty]\t[scanpretty]\t[scanpretty]\t[scanpretty]"
	}
}
::jcapture::usercmd fetchtotal
puts ""
puts "Total cycle count"
puts [::jcapture::vdrscan 32 0]

puts "Saving .vcd file"
set chan [::jcapture::create_vcd cap.vcd]
::jcapture::fifo_to_vcd $chan

puts "Done."
exit


