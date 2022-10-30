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
} F2D deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr) pc <- mkRegU;
    RFile      rf <- mkRFile;
	IMemory  iMem <- mkIMemory;
    DMemory  dMem <- mkDMemory;
    CsrFile  csrf <- mkCsrFile;

    Bool memReady = iMem.init.done() && dMem.init.done();

	// TODO: complete implementation of this processor
    Reg#(Maybe#(F2D)) f2d <- mkReg(tagged Invalid);

    rule doPipeline if (csrf.started);
        let inst = iMem.req(pc);
        let ppc = pc + 4;
        let newIR = tagged Valid F2D { inst: inst, pc: pc, ppc: ppc };

        // trace - print the instruction
        $display("pc: %h inst: (%h) expanded: ", pc, inst, showInst(inst));

        if (f2d matches tagged Valid .ir) begin
            let irinst = ir.inst;
            let irpc = ir.pc;
            let irppc = ir.ppc;
            let dInst = decode(irinst);
            let rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
            let rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
            let csrVal = csrf.rd(fromMaybe(?, dInst.csr));

            let eInst  = exec(dInst, rVal1, rVal2, irpc, irppc, csrVal);

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
                newIR = tagged Invalid;
                ppc = eInst.addr;
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

        pc <= ppc; f2d <= newIR;
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

