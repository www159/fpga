//=====================================================================
//
// Designer   : Yili Gong
//
// Description:
// As part of the project of Computer Organization Experiments, Wuhan University
// In spring 2021
// The datapath of the pipeline.
// ====================================================================

`include "xgriscv_defines.v"

module datapath(
	input                    clk, reset,

	input [`INSTR_SIZE-1:0]  instrF, 	 // from instructon memory
	output[`ADDR_SIZE-1:0] 	 pcF, 		   // to instruction memory

	input [`XLEN-1:0]	       readdataM, // from data memory: read data
  output[`XLEN-1:0]        aluoutM, 	 // to data memory: address
 	output[`XLEN-1:0]	       writedataM,// to data memory: write data
  output			                memwriteM,	// to data memory: write enable
	
	// from controller
	input [4:0]		            immctrlD,
	input			                 itype, jalD, jalrD, bunsignedD, pcsrcD,
	input [3:0]		            aluctrlD,
	input [1:0]		            alusrcaD,
	input			                 alusrcbD,
	input			                 memwriteD, lunsignedD,
	input [1:0]		          	 lwhbD, swhbD,  
	input          		        memtoregD, regwriteD,
	
  	// to controller
	output [6:0]		           opD,
	output [2:0]		           funct3D,
	output [6:0]		           funct7D,
	output [4:0] 		          rdD, rs1D,
	output [11:0]  		        immD,
	output 	       		        zeroD, ltD
	);

	// next PC logic (operates in fetch and decode)
	wire [`ADDR_SIZE-1:0]	 pcplus4F, nextpcF, pcbranchD, pcadder2aD, pcadder2bD, pcbranch0D;
	mux2 #(`ADDR_SIZE)	    pcsrcmux(pcplus4F, pcbranchD, pcsrcD, nextpcF);
	
	// Fetch stage logic
	pcenr      	 pcreg(clk, reset, 1'b1, nextpcF, pcF);
	addr_adder  	pcadder1(pcF, `ADDR_SIZE'b100, pcplus4F);

	///////////////////////////////////////////////////////////////////////////////////
	// IF/ID pipeline registers
	wire [`INSTR_SIZE-1:0]	instrD;
	wire [`ADDR_SIZE-1:0]	pcD, pcplus4D;
	wire flushD = 0;

	floprc #(`INSTR_SIZE) 	pr1D(clk, reset, flushD, instrF, instrD);     // instruction
	floprc #(`ADDR_SIZE)	  pr2D(clk, reset, flushD, pcF, pcD);           // pc
	floprc #(`ADDR_SIZE)	  pr3D(clk, reset, flushD, pcplus4F, pcplus4D); // pc+4

	// Decode stage logic
	wire [`RFIDX_WIDTH-1:0] rs2D;
	assign  opD 	= instrD[6:0];
	assign  rdD     = instrD[11:7];
	assign  funct3D = instrD[14:12];
	assign  rs1D    = instrD[19:15];
	assign  rs2D   	= instrD[24:20];
	assign  funct7D = instrD[31:25];
	assign  immD    = instrD[31:20];

	// immediate generate
	wire [11:0]  iimmD = instrD[31:20];
	wire [11:0]		simmD	= 12'b0;
	wire [11:0]  bimmD	= 20'b0;
	wire [19:0]		uimmD	= instrD[31:12];
	wire [19:0]  jimmD	= 20'b0;
	wire [`XLEN-1:0]	immoutD, shftimmD;
	wire [`XLEN-1:0]	rdata1D, rdata2D, wdataW;
	wire [`RFIDX_WIDTH-1:0]	waddrW;

	imm 	im(iimmD, simmD, bimmD, uimmD, jimmD, immctrlD, immoutD);

	// register file (operates in decode and writeback)
	regfile rf(clk, rs1D, rs2D, rdata1D, rdata2D, regwriteW, waddrW, wdataW);

	///////////////////////////////////////////////////////////////////////////////////
	// ID/EX pipeline registers

	// for control signals
	wire       regwriteE, memwriteE, alusrcbE;
	wire [1:0] alusrcaE;
	wire [3:0] aluctrlE;
	wire 	     flushE = 0;
	floprc #(9) regE(clk, reset, flushE,
                  {regwriteD, memwriteD, alusrcaD, alusrcbD, aluctrlD}, 
                  {regwriteE, memwriteE, alusrcaE, alusrcbE, aluctrlE});
  
	// for data
	wire [`XLEN-1:0]	srca1E, srcb1E, immoutE, srcaE, srcbE, aluoutE;
	wire [`RFIDX_WIDTH-1:0] rdE;
	wire [`ADDR_SIZE-1:0] 	pcE, pcplus4E;
	floprc #(`XLEN) 	pr1E(clk, reset, flushE, rdata1D, srca1E);        	// data from rs1
	floprc #(`XLEN) 	pr2E(clk, reset, flushE, rdata2D, srcb1E);         // data from rs2
	floprc #(`XLEN) 	pr3E(clk, reset, flushE, immoutD, immoutE);        // imm output
 	floprc #(`RFIDX_WIDTH)  pr6E(clk, reset, flushE, rdD, rdE);         // rd
 	floprc #(`ADDR_SIZE)	pr8E(clk, reset, flushE, pcD, pcE);            // pc
 	floprc #(`ADDR_SIZE)	pr9E(clk, reset, flushD, pcplus4D, pcplus4E);  // pc+4

	// execute stage logic
	mux3 #(`XLEN)  srcamux(srca1E, 0, pcE, alusrcaE, srcaE);     // alu src a mux
	mux2 #(`XLEN)  srcbmux(srcb1E, immoutE, alusrcbE, srcbE);			 // alu src b mux

	alu alu(srcaE, srcbE, 5'b0, aluctrlE, aluoutE, overflowE, zeroE, ltE, geE);

	///////////////////////////////////////////////////////////////////////////////////
	// EX/MEM pipeline registers
	// for control signals
	wire 		regwriteM;
	wire 		flushM = 0;
	floprc #(2) 	regM(clk, reset, flushM,
                  	{regwriteE, memwriteE},
                  	{regwriteM, memwriteM});

	// for data
 	wire [`RFIDX_WIDTH-1:0]	 rdM;
	floprc #(`XLEN) 	        pr1M(clk, reset, flushM, aluoutE, aluoutM);
	floprc #(`RFIDX_WIDTH) 	 pr3M(clk, reset, flushM, rdE, rdM);
	
	// mem stage logic
	

  ///////////////////////////////////////////////////////////////////////////////////
  // MEM/WB pipeline registers
  // for control signals
  wire flushW = 0;
	floprc #(1) regW(clk, reset, flushW, {regwriteM}, {regwriteW});

  // for data
  wire[`XLEN-1:0]		       aluoutW;
  wire[`RFIDX_WIDTH-1:0]	 rdW;

  floprc #(`XLEN) 	pr1W(clk, reset, flushW, aluoutM, aluoutW);
  floprc #(`RFIDX_WIDTH) pr2W(clk, reset, flushW, rdM, rdW);
	
	// write-back stage logic
	assign wdataW = aluoutW;
	assign waddrW = rdW;

endmodule