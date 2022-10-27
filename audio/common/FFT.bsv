
import ClientServer::*;
import Complex::*;
import Counter::*;
import FIFO::*;
import FixedPoint::*;
import SpecialFIFOs::*;
import Reg6375::*;
import GetPut::*;
import Real::*;
import Vector::*;

import AudioProcessorTypes::*;

// typedef Server#(
//   Vector#(FFT_POINTS, ComplexSample),
//   Vector#(FFT_POINTS, ComplexSample)
// ) FFT;

typedef Server#(
  Vector#(fft_points, Complex#(cmplxd)),
  Vector#(fft_points, Complex#(cmplxd))
) FFT#(numeric type fft_points, type cmplxd);

// Get the appropriate twiddle factor for the given stage and index.
// This computes the twiddle factor statically.
function Complex#(cmplxd) getTwiddle(
  Integer stage,
  Integer index,
  Integer points
) provisos(RealLiteral#(cmplxd));
  Integer i = ((2*index)/(2 ** (log2(points)-stage))) * (2 ** (log2(points)-stage));
  return cmplx(fromReal(cos(fromInteger(i)*pi/fromInteger(points))),
                fromReal(-1*sin(fromInteger(i)*pi/fromInteger(points))));
endfunction

// Generate a table of all the needed twiddle factors.
// The table can be used for looking up a twiddle factor dynamically.
typedef Vector#(
  TLog#(fft_points),
  Vector#(TDiv#(fft_points, 2), Complex#(cmplxd))
) TwiddleTable#(numeric type fft_points, type cmplxd);
function TwiddleTable#(fft_points, cmplxd) genTwiddles()
provisos(Add#(2, a__, fft_points), RealLiteral#(cmplxd));
  TwiddleTable#(fft_points, cmplxd) twids = newVector;
  for (Integer s = 0; s < valueof(TLog#(fft_points)); s = s + 1) begin
    for (Integer i = 0; i < valueof(TDiv#(fft_points, 2)); i = i + 1) begin
        twids[s][i] = getTwiddle(s, i, valueof(fft_points));
    end
  end
  return twids;
endfunction
// typedef Vector#(FFT_LOG_POINTS, Vector#(TDiv#(FFT_POINTS, 2), ComplexSample)) TwiddleTable;
// function TwiddleTable genTwiddles();
//   TwiddleTable twids = newVector;
//   for (Integer s = 0; s < valueof(FFT_LOG_POINTS); s = s+1) begin
//     for (Integer i = 0; i < valueof(TDiv#(FFT_POINTS, 2)); i = i+1) begin
//         twids[s][i] = getTwiddle(s, i, valueof(FFT_POINTS));
//     end
//   end
//   return twids;
// endfunction


// Given the destination location and the number of points in the fft, return
// the source index for the permutation.
function Integer permute(Integer dst, Integer points);
  Integer src = ?;
  if (dst < points/2) begin
      src = dst*2;
  end else begin
      src = (dst - points/2)*2 + 1;
  end
  return src;
endfunction

// Reorder the given vector by swapping words at positions
// corresponding to the bit-reversal of their indices.
// The reordering can be done either as as the
// first or last phase of the FFT transformation.
function Vector#(fft_points, Complex#(cmplxd)) bitReverse(
  Vector#(fft_points, Complex#(cmplxd)) inVector
) provisos(Add#(2, a__, fft_points), RealLiteral#(cmplxd));
  Vector#(fft_points, Complex#(cmplxd)) outVector = newVector();
  for(Integer i = 0; i < valueOf(fft_points); i = i+1) begin   
      Bit#(TLog#(fft_points)) reversal = reverseBits(fromInteger(i));
      outVector[reversal] = inVector[i];           
  end  
  return outVector;
endfunction

// 2-way Butterfly
function Vector#(2, Complex#(cmplxd)) bfly2(Vector#(2, Complex#(cmplxd)) t, Complex#(cmplxd) k)
provisos(RealLiteral#(cmplxd), Arith#(Complex::Complex#(cmplxd)));
// provisos(Arith#(Complex::Complex#(cmplxd)));
  Complex#(cmplxd) m = t[1] * k;

  Vector#(2, Complex#(cmplxd)) z = newVector();
  z[0] = t[0] + m;
  z[1] = t[0] - m; 

  return z;
endfunction

// Perform a single stage of the FFT, consisting of butterflys and a single
// permutation.
// We pass the table of twiddles as an argument so we can look those up
// dynamically if need be.
function Vector#(fft_points, Complex#(cmplxd)) stage_ft(
  TwiddleTable#(fft_points, cmplxd) twiddles,
  Bit#(TLog#(TLog#(fft_points))) stage,
  Vector#(fft_points, Complex#(cmplxd)) stage_in
) provisos(RealLiteral#(cmplxd), Add#(2, a__, fft_points), Arith#(cmplxd));
  Vector#(fft_points, Complex#(cmplxd)) stage_temp = newVector();
  for(Integer i = 0; i < (valueof(fft_points)/2); i = i+1) begin    
    Integer idx = i * 2;
    let twid = twiddles[stage][i];
    let y = bfly2(takeAt(idx, stage_in), twid);

    stage_temp[idx]   = y[0];
    stage_temp[idx+1] = y[1];
  end 

  Vector#(fft_points, Complex#(cmplxd)) stage_out = newVector();
  for (Integer i = 0; i < valueof(fft_points); i = i+1) begin
    stage_out[i] = stage_temp[permute(i, valueof(fft_points))];
  end
  return stage_out;
endfunction

// Define the stage_f function which uses the generated twiddles.
function Vector#(fft_points, Complex#(cmplxd)) stage_f(
  TwiddleTable#(fft_points, cmplxd) twiddles,
  Bit#(TLog#(TLog#(fft_points))) stage,
  Vector#(fft_points, Complex#(cmplxd)) stage_in
) provisos(Add#(2, a__, fft_points), RealLiteral#(cmplxd), Arith#(cmplxd));
  return stage_ft(twiddles, stage, stage_in);
endfunction

module mkCombinationalFFT (FFT#(fft_points, cmplxd))
provisos(
  Add#(2, a__, fft_points),
  RealLiteral#(cmplxd),
  Arith#(cmplxd),
  Bits#(Vector::Vector#(fft_points, Complex::Complex#(cmplxd)), b__)
);
  // Statically generate the twiddle factors table.
  TwiddleTable#(fft_points, cmplxd) twiddles = genTwiddles();

  FIFO#(Vector#(fft_points, Complex#(cmplxd))) inputFIFO  <- mkFIFO(); 
  FIFO#(Vector#(fft_points, Complex#(cmplxd))) outputFIFO <- mkFIFO(); 

  // This rule performs fft using a big mass of combinational logic.
  rule comb_fft;

    Vector#(TAdd#(1, TLog#(fft_points)), Vector#(fft_points, Complex#(cmplxd))) stage_data = newVector();
    stage_data[0] = inputFIFO.first();
    inputFIFO.deq();

    for(Integer stage = 0; stage < valueof(TLog#(fft_points)); stage=stage+1) begin
        stage_data[stage+1] = stage_f(twiddles, fromInteger(stage), stage_data[stage]);  
    end

    outputFIFO.enq(stage_data[valueof(TLog#(fft_points))]);
  endrule

  interface Put request;
    method Action put(Vector#(fft_points, Complex#(cmplxd)) x);
        inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response = toGet(outputFIFO);
endmodule

module mkLinearFFT(FFT#(fft_points, cmplxd))
provisos(
  Add#(2, a__, fft_points),
  RealLiteral#(cmplxd),
  Arith#(cmplxd),
  Bits#(Vector::Vector#(fft_points, Complex::Complex#(cmplxd)), b__)
);
  // Statically generate the twiddle factors table.
  TwiddleTable#(fft_points, cmplxd) twiddles = genTwiddles();

  FIFO#(Vector#(fft_points, Complex#(cmplxd))) inputFIFO  <- mkFIFO(); 
  Vector#(TLog#(fft_points), FIFO#(Vector#(fft_points, Complex#(cmplxd)))) outputFIFO <- replicateM(mkFIFO()); 

  rule first_stage;
    Integer init_stage_idx = 0;
    let stage_input = inputFIFO.first();
    inputFIFO.deq();

    let stage_output = stage_f(twiddles, fromInteger(init_stage_idx), stage_input);
    outputFIFO[init_stage_idx].enq(stage_output);
  endrule

  for (Integer stage_idx = 1; stage_idx < valueOf(TLog#(fft_points)); stage_idx = stage_idx + 1) begin
    rule linear_fft;
        let stage_in = outputFIFO[stage_idx - 1].first();
        outputFIFO[stage_idx - 1].deq();

        let stage_out = stage_f(twiddles, fromInteger(stage_idx), stage_in);
        outputFIFO[stage_idx].enq(stage_out);
    endrule
  end

  interface Put request;
    method Action put(Vector#(fft_points, Complex#(cmplxd)) x);
        inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response = toGet(outputFIFO[valueOf(TLog#(fft_points)) - 1]);
endmodule
/*
(* synthesize *)
module mkCircularFFT1(FFT);
  // Statically generate the twiddle factors table.
  TwiddleTable twiddles = genTwiddles();

  FIFO#(Vector#(FFT_POINTS, ComplexSample)) inputFIFO <- mkLFIFO();
  FIFO#(Vector#(FFT_POINTS, ComplexSample)) outputFIFO  <- mkFIFO();

  Reg#(Vector#(FFT_POINTS, ComplexSample)) stage_out <- mkReg(newVector);
  let stage_num_max = fromInteger(valueOf(FFT_LOG_POINTS));
//   Counter#(TLog#(FFT_LOG_POINTS)) cntr <- mkCounter(0);
  Counter#(8) cntr <- mkCounter(0);
  let cntr_val = cntr.value();

  rule stage_step;
    if (cntr_val == 0) begin
      inputFIFO.deq();
    end

    let stage_input = case (cntr_val)
      0 : inputFIFO.first();
      default: stage_out;
    endcase;

    let stage_result = stage_f(twiddles, truncate(pack(cntr_val)), stage_input);

    if (cntr_val == stage_num_max - 1) begin
      outputFIFO.enq(stage_result);
      cntr.clear();
    end
    else begin
      stage_out <= stage_result;
      cntr.up();
    end
  endrule

  interface Put request;
    method Action put(Vector#(FFT_POINTS, ComplexSample) x);
      inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response = toGet(outputFIFO);
endmodule

(* synthesize *)
module mkCircularFFT2(FFT);
  // Statically generate the twiddle factors table.
  TwiddleTable twiddles = genTwiddles();

  FIFO#(Vector#(FFT_POINTS, ComplexSample)) inputFIFO <- mkLFIFO();
  FIFO#(Vector#(FFT_POINTS, ComplexSample)) outputFIFO  <- mkFIFO();

  FIFO#(Vector#(FFT_POINTS, ComplexSample)) stageFIFO <- mkLFIFO();
  Wire#(Vector#(FFT_POINTS, ComplexSample)) stage_result <- mkWire();
  let stage_num_max = fromInteger(valueOf(FFT_LOG_POINTS));
//   Counter#(TLog#(FFT_LOG_POINTS)) cntr <- mkCounter(0);
  Counter#(8) cntr <- mkCounter(0);
  let cntr_val = cntr.value();

  (* descending_urgency = "stage_deq, stage_enq, enter" *)
  rule stage_deq;
    stageFIFO.deq();
    let stage_input = stageFIFO.first();
    stage_result <= stage_f(twiddles, truncate(pack(cntr_val)), stage_input);
  endrule

  rule stage_enq (cntr_val < stage_num_max);
    if (cntr_val == stage_num_max - 1) begin
      outputFIFO.enq(stage_result);
      cntr.clear();
    end
    else begin
      stageFIFO.enq(stage_result);
      cntr.up();
    end
  endrule

  rule enter;
    let fft_input = inputFIFO.first();
    inputFIFO.deq();
    stageFIFO.enq(fft_input);
  endrule

  interface Put request;
    method Action put(Vector#(FFT_POINTS, ComplexSample) x);
      inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response = toGet(outputFIFO);
endmodule

(* synthesize *)
module mkCircularFFT3(FFT);
  // Statically generate the twiddle factors table.
  TwiddleTable twiddles = genTwiddles();

  FIFO#(Vector#(FFT_POINTS, ComplexSample)) inputFIFO <- mkLFIFO();
  FIFO#(Vector#(FFT_POINTS, ComplexSample)) stageFIFO <- mkLFIFO();
  Wire#(Vector#(FFT_POINTS, ComplexSample)) stage_result <- mkWire();
  let stage_num_max = fromInteger(valueOf(FFT_LOG_POINTS));
//   Counter#(TLog#(FFT_LOG_POINTS)) cntr <- mkCounter(0);
  Counter#(8) cntr <- mkCounter(0);
  let cntr_val = cntr.value();

  (* descending_urgency = "response_get, stage_pop, stage_push, stage_init" *)
  rule stage_pop;
    stageFIFO.deq();
    let stage_input = stageFIFO.first();
    stage_result <= stage_f(twiddles, truncate(pack(cntr_val)), stage_input);
  endrule

  rule stage_push (cntr_val < stage_num_max);
    stageFIFO.enq(stage_result);
    cntr.up();
  endrule

  rule stage_init;
    let fft_input = inputFIFO.first();
    inputFIFO.deq();
    stageFIFO.enq(fft_input);
  endrule

  interface Put request;
    method Action put(Vector#(FFT_POINTS, ComplexSample) x);
      inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(Vector#(FFT_POINTS, ComplexSample)) get if (cntr_val == stage_num_max);
      let result = stageFIFO.first();
      stageFIFO.deq();
      cntr.clear();
      return result;
    endmethod
  endinterface
endmodule
*/

module mkCircularFFT4(FFT#(fft_points, cmplxd))
provisos(
  Add#(2, a__, fft_points),
  RealLiteral#(cmplxd),
  Arith#(cmplxd),
  Bits#(Vector::Vector#(fft_points, Complex::Complex#(cmplxd)), b__)
);
  // Statically generate the twiddle factors table.
  TwiddleTable#(fft_points, cmplxd) twiddles = genTwiddles();

  FIFO#(Vector#(fft_points, Complex#(cmplxd))) stageFIFO <- mkLFIFO();
  Wire#(Vector#(fft_points, Complex#(cmplxd))) stage_result <- mkWire();
  let stage_num_max = fromInteger(valueOf(TLog#(fft_points)));
  Counter#(TLog#(TLog#(fft_points))) cntr <- mkCounter(0);
  // Counter#(8) cntr <- mkCounter(0);
  let cntr_val = cntr.value();

  // (* descending_urgency = "response_get, stage_pop, stage_push, request_put" *)
  rule stage_pop (cntr_val < stage_num_max);
    stageFIFO.deq();
    let stage_input = stageFIFO.first();
    stage_result <= stage_f(twiddles, truncate(pack(cntr_val)), stage_input);
  endrule

  rule stage_push (cntr_val < stage_num_max);
    stageFIFO.enq(stage_result);
    cntr.up();
  endrule

  interface Put request;
    method Action put(Vector#(fft_points, Complex#(cmplxd)) x);
      stageFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response;
    method ActionValue#(Vector#(fft_points, Complex#(cmplxd))) get if (cntr_val == stage_num_max);
      let result = stageFIFO.first();
      stageFIFO.deq();
      cntr.clear();
      return result;
    endmethod
  endinterface
endmodule

// Wrapper around The FFT module we actually want to use
module mkFFT (FFT#(fft_points, complex)) provisos(Add#(2, a__, fft_points), Arith#(complex), RealLiteral#(complex), Bits#(complex, c__));
    // let fft <- mkCombinationalFFT();
    let fft <- mkLinearFFT();
    // FFT fft <- mkCircularFFT1();
    // FFT fft <- mkCircularFFT2();
    // FFT fft <- mkCircularFFT3();
    // let fft <- mkCircularFFT4();

    interface Put request = fft.request;
    interface Get response = fft.response;
endmodule

// Inverse FFT, based on the mkFFT module.
// ifft[k] = fft[N-k]/N
module mkIFFT (FFT#(fft_points, complex)) provisos(Add#(2, a__, fft_points), Arith#(complex), RealLiteral#(complex), Bits#(complex, c__), Bitwise#(complex));

    let fft <- mkFFT();
    FIFO#(Vector#(fft_points, Complex#(complex))) outfifo <- mkFIFO();

    Integer n = valueof(fft_points);
    Integer lgn = valueof(TLog#(fft_points));

    function Complex#(complex) scaledown(Complex#(complex) x);
        return cmplx(x.rel >> lgn, x.img >> lgn);
    endfunction

    rule inversify (True);
        let x <- fft.response.get();
        Vector#(fft_points, Complex#(complex)) rx = newVector;

        for (Integer i = 0; i < n; i = i+1) begin
            rx[i] = x[(n - i)%n];
        end
        outfifo.enq(map(scaledown, rx));
    endrule

    interface Put request = fft.request;
    interface Get response = toGet(outfifo);

endmodule

