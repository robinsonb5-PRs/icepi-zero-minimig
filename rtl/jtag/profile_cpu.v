`default_nettype none

module profile_cpu (
	input wire clk,
	input wire reset_n,
	input wire clkena,
	input wire  [1:0] cpustate,
	input wire sel_chip,
	input wire sel_kick,
	input wire sel_fast24,
	input wire sel_fast32,
	output reg reset_n_out
);

// Sizes of histogram buckets and categories

localparam categories_log2 = 2;

localparam accesstypes_log2 = 2;

localparam buckets_log2 = 4;

reg active=1'b0;

// Counter
reg [buckets_log2-1:0] counter;
reg [categories_log2-1:0] category;
reg [accesstypes_log2-1:0] accesstype;

always @(posedge clk) begin
	if(sel_chip)
		category<=2'b00;
	else if(sel_kick)
		category<=2'b01;
	else if(sel_fast24)
		category<=2'b10;
	else if(sel_fast32)
		category<=2'b11;
		
	accesstype<=cpustate;

	if(active && !(&counter))	// Saturate counter at maximum
		counter<=counter+1;
	if(clkena)
		counter <= 0;
end

localparam addr_log2 = categories_log2 + accesstypes_log2 + buckets_log2;

reg [31:0] storage [2**addr_log2];
reg [addr_log2-1:0] wrptr;
reg [addr_log2-1:0] rdptr;

// Write side

localparam S_INIT = 0;
localparam S_CLR = 1;
localparam S_IDLE = 2;
localparam S_READ = 3;
localparam S_WRITE = 4;
reg [3:0] state;

reg [31:0] storage_q;
always @(posedge clk) begin
	case(state)
		S_INIT: begin
			wrptr<=1;
			state<=S_CLR;
		end	
		S_CLR: begin
			storage[wrptr]<=0;
			wrptr<=wrptr+1;
			if(!(|wrptr))
				state<=S_IDLE;
		end
		S_IDLE: begin
			if(clkena && active) begin
				rdptr<={category,counter[buckets_log2-1:0],accesstype};
				wrptr<={category,counter[buckets_log2-1:0],accesstype};
				state<=S_READ;
			end
		end
		S_READ:
			state <= S_WRITE;
		S_WRITE: begin
			storage[wrptr]<=storage_q+ (&storage_q ? 1'b0 : 1'b1); // Clamp to prevent overflow
			state <= S_IDLE;
		end

	endcase

	storage_q<=storage[rdptr];

	if(jtag_reset || !reset_n)
		state<=S_INIT;

end


reg [31:0] clkenacounter;

always @(posedge clk) begin
	if(clkena && active)
		clkenacounter<=clkenacounter + (&clkenacounter ? 1'b0 : 1'b1); // Clamp to prevent overflow
	if(jtag_reset || !reset_n)
		clkenacounter<=0;
end


// Virtual JTAG remote interface:

// Commands:
//   0  -  reset counters
//   1  -  enable monitoring
//   2  -  disable monitoring
//   3  -  fetch data
//   4  -  fetch clkenacount
//   5  -  external reset

// Custom interface

reg [31:0] jtag_user_d;    // 32-bit data in and out
wire [31:0] jtag_user_q;
wire jtag_cmd_stb;         // Command has been updated
wire jtag_user_upd;        // A word has been transferred
wire [3:0] jtag_cmd;

reg [addr_log2-1:0] rdptr_j;

// Select between data sources based on command
always @(posedge clk) begin
	case(jtag_cmd)
		4'h3: jtag_user_d <= storage[rdptr_j];
		4'h4: jtag_user_d <= clkenacounter;
		default: jtag_user_d <= 0;
	endcase
end


// Might as well capture CPU signals while we're at it:
reg [30:0] jtag_capture_d=0;

always @(posedge clk) begin
	jtag_capture_d[0] <= clkena;
	jtag_capture_d[2:1] <= cpustate;
	jtag_capture_d[3] <= sel_chip;
	jtag_capture_d[4] <= sel_kick;
	jtag_capture_d[5] <= sel_fast24;
	jtag_capture_d[6] <= sel_fast32;
	jtag_capture_d[30:7] <= 0;
end

reg jtag_reset;
reg jtag_report;

always @(posedge clk) begin
	jtag_report<=1'b0;
	reset_n_out <= 1'b1;
	jtag_reset<=1'b0;

	if(jtag_cmd_stb) begin
		case(jtag_cmd) // Interpret the highest 8 bits as a command byte
			4'h0: jtag_reset <= 1'b1;
			4'h1: active <= 1'b1;
			4'h2: active <= 1'b0;
			4'h3: begin
				active <= 1'b0;
				jtag_report<=1'b1;
			end
			4'h4: jtag_report<=1'b1;
			4'h5: reset_n_out <= 1'b0;
		endcase
	end
	
	if(!reset_n)
		active<=1'b0;
end


// Plumbing

always @(posedge clk) begin

	if(jtag_user_upd) begin // Data has been transferred
		case(jtag_cmd)
			4'h3: rdptr_j<=rdptr_j+1;
			default: ;
		endcase
	end

	if(jtag_report)
		rdptr_j<=0;

	if(!reset_n)
		rdptr_j<={addr_log2{1'b1}};
end

jcapture #(
	.capturedepth(8),       // Capturing isn't our main goal here, so relatively small FIFO.
	.runlengthencoding(0),  // Turn off RLE to keep FMax high
	.designid(16'h1010)     // Arbitrary ID code so our Tcl script can be sure it's talking to the right design.
) jtag_inst (
	.clk(clk),
	.reset_n(reset_n),
	.stb(1'b1),
	.capture_d(jtag_capture_d),
	.user_ir(jtag_cmd),
	.user_ir_update(jtag_cmd_stb),
	.user_d(jtag_user_d),
	.user_q(jtag_user_q),
	.user_update(jtag_user_upd)	
);

endmodule

