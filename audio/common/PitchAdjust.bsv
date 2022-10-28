
import ClientServer::*;
import FIFO::*;
import GetPut::*;
import FixedPoint::*;
import Cordic::*;

import Vector::*;

import Complex::*;
import ComplexMP::*;

typedef Server#(
	Vector#(nbins, ComplexMP#(isize, fsize, psize)),
	Vector#(nbins, ComplexMP#(isize, fsize, psize))
) PitchAdjust#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);

interface SettablePitchAdjust#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);
	interface PitchAdjust#(nbins, isize, fsize, psize) adjust;
	interface Put#(FixedPoint#(isize, fsize)) setfactor;
endinterface

// s - the amount each window is shifted from the previous window.
//
// factor - the amount to adjust the pitch.
//  1.0 makes no change. 2.0 goes up an octave, 0.5 goes down an octave, etc...
module mkPitchAdjust2(Integer s, FixedPoint#(isize, fsize) factor, PitchAdjust#(nbins, isize, fsize, psize) ifc)
provisos(Add#(a__, TAdd#(3, TLog#(nbins)), isize), Add#(psize, b__, isize), Add#(TAdd#(1, TLog#(TAdd#(3, nbins))), c__, isize), Add#(d__, psize, TAdd#(isize, isize)));
	FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) inputFIFO  <- mkFIFO();
	FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) outputFIFO <- mkFIFO();

	Vector#(nbins, Reg#(Phase#(psize))) inPhases  <- replicateM(mkReg(0));
	Vector#(nbins, Reg#(Phase#(psize))) outPhases <- replicateM(mkReg(0));
	Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) out <- mkReg(replicate(cmplxmp(0, 0)));
	Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) in <- mkReg(replicate(cmplxmp(0, 0)));

	Reg#(Int#(TAdd#(1, TLog#(TAdd#(3, nbins))))) i <- mkReg(fromInteger(valueof(nbins)) + 1);

	//Reg#(FixedPoint#(misize, mfsize)) multiplied <- mkRegU();
	let multiplied <- mkRegU();
	Reg#(Int#(3)) abcd <- mkReg(0);
	Reg#(Int#(TAdd#(3, TLog#(nbins)))) binR <- mkRegU();
	Reg#(Int#(TAdd#(3, TLog#(nbins)))) nbinR <- mkRegU();
	let magR <- mkRegU();
	let iFxptR <- mkRegU();
	let ip1FxptR <- mkRegU();
	Reg#(Int#(psize)) dphaseR <- mkRegU();

	rule pitchAdjustIn(i == fromInteger(valueof(nbins)) + 1);
		in <= inputFIFO.first();
		inputFIFO.deq();

		out <= replicate(cmplxmp(0, 0));
		i <= 0;
	endrule

	rule pitchAdjustA(i < fromInteger(valueof(nbins)) && abcd == 0);
		let phase = phaseof(in[i]);
		let mag = in[i].magnitude;
		
		let dphase = phase - inPhases[i];
		inPhases[i] <= phase;
		magR <= mag;
		dphaseR <= dphase;
		abcd <= -1;
	endrule

	rule pitchAdjustB(i < fromInteger(valueof(nbins)) && abcd == -1);
		iFxptR <= fromInt(i);
		ip1FxptR <= fromInt(i + 1);
		abcd <= 1;
	endrule

	rule pitchAdjustB2(i < fromInteger(valueof(nbins)) && abcd == 1);
		Int#(TAdd#(3, TLog#(nbins))) bin = truncate(fxptGetInt(iFxptR * factor));
		Int#(TAdd#(3, TLog#(nbins))) nbin = truncate(fxptGetInt(ip1FxptR * factor));
		binR <= bin;
		nbinR <= nbin;
		abcd <= 2;
	endrule

	rule pitchAdjustC(i < fromInteger(valueof(nbins)) && abcd == 2);
		if (nbinR != binR && binR >= 0 && binR < fromInteger(valueof(nbins))) begin
			FixedPoint#(isize, fsize) dphaseFxpt = fromInt(dphaseR);
			multiplied <= fxptMult(dphaseFxpt, factor);
		end
		abcd <= 3;
	endrule

	rule pitchAdjustD(i < fromInteger(valueof(nbins)) && abcd == 3);
		if (nbinR != binR && binR >= 0 && binR < fromInteger(valueof(nbins))) begin
			let multInt = fxptGetInt(multiplied);
			let shifted = truncate(multInt);
			outPhases[binR] <= outPhases[binR] + shifted;
			out[binR] <= cmplxmp(magR, outPhases[binR] + shifted);
		end

		i <= i + 1;
		abcd <= 0;
	endrule

	rule pitchAdjustOut(i == fromInteger(valueof(nbins)));
		outputFIFO.enq(out);
		i <= i + 1;
	endrule

	// interface PitchAdjust adjust;
		interface Put request  = toPut(inputFIFO);
		interface Get response = toGet(outputFIFO);
	// endinterface
endmodule


module mkPitchAdjust(Integer s, SettablePitchAdjust#(nbins, isize, fsize, psize) ifc) provisos (Add#(a__, TAdd#(3, TLog#(nbins)), isize), Add#(b__, psize, isize), Add#(c__, psize, TAdd#(isize, isize)), Add#(TAdd#(1, TLog#(TAdd#(3, nbins))), e__, isize));
	FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) inputFIFO  <- mkFIFO();
	FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) outputFIFO <- mkFIFO();

	Vector#(nbins, Reg#(Phase#(psize))) inPhases  <- replicateM(mkReg(0));
	Vector#(nbins, Reg#(Phase#(psize))) outPhases <- replicateM(mkReg(0));
	Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) out <- mkReg(replicate(cmplxmp(0, 0)));
	Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) in <- mkReg(replicate(cmplxmp(0, 0)));

	Reg#(Maybe#(FixedPoint#(isize, fsize))) factor <- mkReg(tagged Invalid);
	Reg#(Int#(TAdd#(1, TLog#(TAdd#(3, nbins))))) i <- mkReg(fromInteger(valueof(nbins)) + 1);

	//Reg#(FixedPoint#(misize, mfsize)) multiplied <- mkRegU();
	let multiplied <- mkRegU();
	Reg#(Int#(3)) abcd <- mkReg(0);
	Reg#(Int#(TAdd#(3, TLog#(nbins)))) binR <- mkRegU();
	Reg#(Int#(TAdd#(3, TLog#(nbins)))) nbinR <- mkRegU();
	let magR <- mkRegU();
	let iFxptR <- mkRegU();
	let ip1FxptR <- mkRegU();
	Reg#(Int#(psize)) dphaseR <- mkRegU();

	rule pitchAdjustIn(isValid(factor) && i == fromInteger(valueof(nbins)) + 1);
		in <= inputFIFO.first();
		inputFIFO.deq();

		out <= replicate(cmplxmp(0, 0));
		i <= 0;
	endrule

	rule pitchAdjustA(isValid(factor) && i < fromInteger(valueof(nbins)) && abcd == 0);
		let phase = phaseof(in[i]);
		let mag = in[i].magnitude;
		
		let dphase = phase - inPhases[i];
		inPhases[i] <= phase;
		magR <= mag;
		dphaseR <= dphase;
		abcd <= -1;
	endrule

	rule pitchAdjustB(isValid(factor) && i < fromInteger(valueof(nbins)) && abcd == -1);
		iFxptR <= fromInt(i);
		ip1FxptR <= fromInt(i + 1);
		abcd <= 1;
	endrule
	rule pitchAdjustB2(isValid(factor) && i < fromInteger(valueof(nbins)) && abcd == 1);
		Int#(TAdd#(3, TLog#(nbins))) bin = truncate(fxptGetInt(iFxptR * fromMaybe(2, factor)));
		Int#(TAdd#(3, TLog#(nbins))) nbin = truncate(fxptGetInt(ip1FxptR * fromMaybe(2, factor)));
		binR <= bin;
		nbinR <= nbin;
		abcd <= 2;
	endrule

	rule pitchAdjustC(isValid(factor) && i < fromInteger(valueof(nbins)) && abcd == 2);

		if (nbinR != binR && binR >= 0 && binR < fromInteger(valueof(nbins))) begin
			FixedPoint#(isize, fsize) dphaseFxpt = fromInt(dphaseR);
			multiplied <= fxptMult(dphaseFxpt, fromMaybe(2, factor));
		end
		abcd <= 3;
	endrule

	rule pitchAdjustD(isValid(factor) && i < fromInteger(valueof(nbins)) && abcd == 3);
		if (nbinR != binR && binR >= 0 && binR < fromInteger(valueof(nbins))) begin
			let multInt = fxptGetInt(multiplied);
			let shifted = truncate(multInt);
			outPhases[binR] <= outPhases[binR] + shifted;
			out[binR] <= cmplxmp(magR, outPhases[binR] + shifted);
		end

		i <= i + 1;
		abcd <= 0;
	endrule

	rule pitchAdjustOut(isValid(factor) && i == fromInteger(valueof(nbins)));
		outputFIFO.enq(out);
		i <= i + 1;
	endrule

	interface PitchAdjust adjust;
		interface Put request  = toPut(inputFIFO);
		interface Get response = toGet(outputFIFO);
	endinterface

	interface Put setfactor;
		method Action put(FixedPoint#(isize, fsize) x) if (!isValid(factor));
			factor <= tagged Valid x;
			i <= fromInteger(valueof(nbins)) + 1;
		endmethod
	endinterface
endmodule


typedef Server#(
	Vector#(len, a), Vector#(len, b)
) MapModule#(numeric type len, type a, type b);

module [Module] mkMapModule(Module#(Server#(a, b)) f, MapModule#(len, a, b) ifc) provisos (Bits#(Vector::Vector#(len, b), a__), Bits#(Vector::Vector#(len, a), b__));
	FIFO#(Vector#(len, a)) inputFIFO  <- mkFIFO();
	FIFO#(Vector#(len, b)) outputFIFO <- mkFIFO();

	Vector#(len, Server#(a, b)) fs <- replicateM(f);


	// function void putReq(Tuple2#(Server#(a, b), a) t2);
	// 	let {s, x} = t2;
	// 	let _ = s.request.put(x);
	// 	return ?;
	// endfunction

	// function ActionValue#(b) getResp(Server#(a, b) s) = s.response.get();

	rule mapIn(True);
		let xs = inputFIFO.first();
		inputFIFO.deq();

		// let _ = map(putReq, zip(fs, xs));
		for (Integer i = 0; i < valueof(len); i = i + 1) begin
			fs[i].request.put(xs[i]);
		end
	endrule

	rule mapOut(True);
		// let ys = map(getResp, fs);
		Vector#(len, b) ys;
		for (Integer i = 0; i < valueof(len); i = i + 1) begin
			ys[i] <- fs[i].response.get();
		end
		outputFIFO.enq(ys);
	endrule

	interface Put request  = toPut(inputFIFO);
	interface Get response = toGet(outputFIFO);
endmodule

typedef Server#(
	Vector#(len, Complex#(FixedPoint#(isize, fsize))),
	Vector#(len, ComplexMP#(isize, fsize, psize))
) ToMP#(numeric type len, numeric type isize, numeric type fsize, numeric type psize);

module [Module] mkToMP(ToMP#(len, isize, fsize, psize));
	MapModule#(len, Complex#(FixedPoint#(isize, fsize)), ComplexMP#(isize, fsize, psize)) mapMod <- mkMapModule(mkCordicToMagnitudePhase());

	interface Put request = mapMod.request;
	interface Get response = mapMod.response;
endmodule

typedef Server#(
	Vector#(len, ComplexMP#(isize, fsize, psize)),
	Vector#(len, Complex#(FixedPoint#(isize, fsize)))
) FromMP#(numeric type len, numeric type isize, numeric type fsize, numeric type psize);

module [Module] mkFromMP(FromMP#(len, isize, fsize, psize));
	MapModule#(len, ComplexMP#(isize, fsize, psize), Complex#(FixedPoint#(isize, fsize))) mapMod <- mkMapModule(mkCordicFromMagnitudePhase());

	interface Put request = mapMod.request;
	interface Get response = mapMod.response;
endmodule