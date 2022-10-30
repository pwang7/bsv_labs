// TwoStage.bsv
//
// This is a two stage pipelined implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import MemTypes::*;
import MemInit::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;

typedef struct {
	Data inst;
	Addr pc;
	Addr ppc;
    Bit#(1) epoch;
} F2D deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Ehr#(2, Addr) pc <- mkEhrU;
    RFile      rf <- mkRFile;
	IMemory  iMem <- mkIMemory;
    DMemory  dMem <- mkDMemory;
    CsrFile  csrf <- mkCsrFile;

    Bool memReady = iMem.init.done() && dMem.init.done();

	// TODO: complete implementation of this processor
    Ehr#(2, Bit#(1)) epochReg <- mkEhrU;
    Reg#(Maybe#(F2D)) f2d <- mkReg(tagged Invalid);

    rule doFetch if (csrf.started);
        let inst = iMem.req(pc[1]);
        let ppc = pc[1] + 4;
        f2d <= tagged Valid F2D { inst: inst, pc: pc[1], ppc: ppc, epoch: epochReg[1] };
        pc[1] <= ppc;

        // trace - print the instruction
        $display("fetch: PC=%h inst=(%h) expanded: ", pc[1], inst, showInst(inst));
    endrule

    rule doExecute if (csrf.started &&& f2d matches tagged Valid .ir);
        let irepoch = ir.epoch;
        let irinst = ir.inst;
        let irpc = ir.pc;
        let irppc = ir.ppc;
        let dInst = decode(irinst);
        let rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
        let rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
        let csrVal = csrf.rd(fromMaybe(?, dInst.csr));
        $display("decode: rVal1=%h, rVal2=%h, csrVal=%h", rVal1, rVal2, csrVal);

        let eInst  = exec(dInst, rVal1, rVal2, irpc, irppc, csrVal);
        let wrongir = irepoch != epochReg[0];
        $display("execute: wrongir=%b, eInst.brTaken=%b, eInst.addr=%h, ppc=%h", wrongir, eInst.brTaken, eInst.addr, irppc);

        if (!wrongir) begin
            if (eInst.iType == Ld) begin
                eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
            end
            else if (eInst.iType == St) begin
                let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
            end
            else if (eInst.iType == Unsupported) begin
                // check unsupported instruction at commit time. Exiting
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", irpc);
                $finish;
            end

            if (isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
            end

            if (eInst.mispredict) begin
                pc[0] <= eInst.addr;
                epochReg[0] <= epochReg[0] + 1'b1;
            end


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
        end
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc[0] <= startpc;
    endmethod

	interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule

