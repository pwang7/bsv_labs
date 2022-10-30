`include "ConnectalProjectConfig.bsv"

import Clocks::*;
import GetPut::*;

import ProcTypes::*;
import Types::*;
import MemTypes::*;

`ifdef ONECYCLE 
import OneCycle::*;
`endif

`ifdef TWOCYCLE
import TwoCycle::*;
`endif

`ifdef FOURCYCLE
import FourCycle::*;
`endif

`ifdef TWOSTAGE 
import TwoStage::*;
`endif

// `ifdef TWOSTAGEBTB
// import TwoStageBtb::*;
// `endif

interface MemInitRequest;
   method Action done();
   method Action write(Bit#(32) addr, Bit#(32) data);
endinterface

// interface used by software
interface StartRequest;
    // Bit#(n) is the only supported argument type for request methods
    method Action start_dut(Bit#(32) in);
    method Action reset_dut();
endinterface

// interface used by hardware to send a message back to software
interface MyDutIndication;
    // Bit#(n) is the only supported argument type for indication methods
    method Action returnOutput(Bit#(32) out);
    method Action wroteWord(Bit#(8) data);
endinterface

// interface of the connectal wrapper (mkMyDut) of your design
interface MyDut;
    interface StartRequest start;
    interface MemInitRequest init;
    // More sub-interface will be added to support DMA to host memory (if needed in the final project)
endinterface

module mkMyDut#(MyDutIndication indication) (MyDut);
    Reg#(Bool) ready <- mkReg(False);
    // Soft reset generator
    Reg#(Bool) isResetting <- mkReg(False);
    Reg#(Bit#(2)) resetCnt <- mkReg(0);
    Clock connectal_clk <- exposeCurrentClock;
    MakeResetIfc my_rst <- mkReset(1, True, connectal_clk); // inherits parent's reset (hidden) and introduce extra reset method (OR condition)

    // Your design
    let proc <- mkProc(reset_by my_rst.new_rst);

    rule clearResetting if (isResetting);
        resetCnt <= resetCnt + 1;
        if (resetCnt == 3) isResetting <= False;
    endrule

    // Send a message back to sofware whenever the response is ready
    // rule indicationToSoftware;
    //     let d <- proc.cpuToHost;
    //     // $display("out: %d", d);
    //     indication.returnOutput(zeroExtend(pack(d))); // pack casts the "type" of non-Bit#(n) variable into Bit#(n). Physical bits do not change. Just type conversion.
    // endrule
    rule relayMessage;
        let msg <- proc.cpuToHost();
        indication.returnOutput(zeroExtend(pack(msg)));
    endrule

    // Interface used by software (MyDutRequest)
    interface StartRequest start;
        method Action start_dut(Bit#(32) startpc) if (!isResetting && ready);
            $display("Received software req to start pc=%x\n", startpc);
            $fflush(stdout);
            proc.hostToCpu(truncate(startpc)); // unpack casts the type of a Bit#(n) value into a different type, i.e., Sample, which is Int#(16)
        endmethod

        method Action reset_dut;
            my_rst.assertReset; // assert my_rst.new_rst signal
            isResetting <= True;
            ready <= True;
        endmethod
    endinterface

    interface MemInitRequest init;
        method Action done() if (!isResetting && ready);
            $display("Received software req to init mem\n");
            proc.iMemInit.request.put(tagged InitDone);
            proc.dMemInit.request.put(tagged InitDone);
        endmethod

        method Action write(Bit#(32) addr, Bit#(32) data) if (!isResetting && ready);
            // $display("Request %x %x", addr, data);
            indication.wroteWord(0);
            proc.iMemInit.request.put(tagged InitLoad (MemInitLoad {addr: addr, data: data}));
            proc.dMemInit.request.put(tagged InitLoad (MemInitLoad {addr: addr, data: data}));
        endmethod 
    endinterface
endmodule
