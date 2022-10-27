// FourCycle.bsv
//
// This is a four cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import MemTypes::*;
import MemInit::*;
import RFile::*;
import IMemory::*;
import DelayedMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;

typedef struct {
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
} D2E deriving(Bits, Eq);

typedef enum {
	Fetch,
	Decode,
	Execute,
	WriteBack
} Stage deriving(Bits, Eq, FShow);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr)      pc <- mkRegU;
    RFile           rf <- mkRFile;
    IMemory       iMem <- mkIMemory;
    DelayedMemory dMem <- mkDelayedMemory;
    CsrFile       csrf <- mkCsrFile;

    Bool memReady = iMem.init.done() && dMem.init.done();

	// TODO: complete implementation of this processor
    Reg#(Stage) stage <- mkReg(Fetch);
    Reg#(Data) f2d <- mkRegU;
    Reg#(D2E)  d2e <- mkRegU;
    Reg#(ExecInst)  e2w <- mkRegU;

    rule doFetch if (csrf.started && stage == Fetch);
        let inst = iMem.req(pc);
        f2d <= inst;
        stage <= Decode;

        // trace - print the instruction
        $display("fetch: PC=%h inst=(%h) expanded: ", pc, inst, showInst(inst));
    endrule

    rule doDecode if (csrf.started && stage == Decode);
        let inst = f2d;
        let dInst  = decode(inst);
        let rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
        let rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
        let csrVal = csrf.rd(fromMaybe(?, dInst.csr));
        d2e <= D2E { dInst: dInst, rVal1: rVal1, rVal2: rVal2, csrVal: csrVal };
        stage <= Execute;

        $display("decode: rVal1=%h, rVal2=%h, csrVal=%h", rVal1, rVal2, csrVal);
    endrule

    rule doExecute if (csrf.started && stage == Execute);
        let dInst  = d2e.dInst;
        let rVal1  = d2e.rVal1;
        let rVal2  = d2e.rVal2;
        let csrVal = d2e.csrVal;
        let eInst  = exec(dInst, rVal1, rVal2, pc, ?, csrVal);

        if (eInst.iType == Ld) begin
            dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end
        else if (eInst.iType == St) begin
            dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end

        let ppc = pc + 4;
        pc <= eInst.brTaken ? eInst.addr : ppc;

        e2w <= eInst;
        stage <= WriteBack;

        $display("execute: eInst.brTaken=%b, eInst.addr=%h, ppc=%h", eInst.brTaken, eInst.addr, ppc);
    endrule

    rule doWriteBack if (csrf.started && stage == WriteBack);
        let eInst = e2w;
        if (isValid(eInst.dst)) begin
            let data = eInst.iType == Ld ? dMem.first: eInst.data;
            rf.wr(fromMaybe(?, eInst.dst), data);
        end

        if (eInst.iType == Ld) begin
            dMem.deq;
        end
        
        stage <= Fetch;


		// These codes are checking invalid CSR index
		// you could uncomment it for debugging
		// 
		// check invalid CSR read
		if (eInst.iType == Csrr) begin
			let csrIdx = fromMaybe(0, eInst.csr);
			case (csrIdx)
				csrCycle, csrInstret, csrMhartid: begin
					$display("CSRR reads 0x%0x", eInst.data);
				end
				default: begin
					$fwrite(stderr, "ERROR: read invalid CSR 0x%0x. Exiting\n", csrIdx);
					$finish;
				end
			endcase
		end
		// check invalid CSR write
		if (eInst.iType == Csrw) begin
			let csrIdx = fromMaybe(0, eInst.csr);
			if (csrIdx != csrMtohost) begin
				$fwrite(stderr, "ERROR: invalid CSR index = 0x%0x. Exiting\n", csrIdx);
				$finish;
			end
			else begin
				$display("CSRW writes 0x%0x", eInst.data);
			end
		end

        // CSR write for sending data to host & stats
        csrf.wr( (eInst.iType == Csrw ? eInst.csr : Invalid), eInst.data);

        $display(
            "writeback: isValid(eInst.dst)=%b, eInst.dst=%h, eInst.iType=%h, PC=%h",
            isValid(eInst.dst), fromMaybe(?, eInst.dst), eInst.iType, pc
        );
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc <= startpc;
    endmethod

    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule

