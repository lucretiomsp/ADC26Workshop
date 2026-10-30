"PlainVerb in Phausto: the same Schroeder reverb as plainverb.dsp, built from primitives.
Each Faust definition becomes a block, so every call builds fresh boxes.
In a Playground, evaluate the definitions once, then Listen, Stop or Export."

"Controls"
size := PhHSlider new label: 'size' values: #( 0.85 0 0.95 0.01 ).
damp := PhHSlider new label: 'damp' values: #( 0.4 0 0.9 0.01 ).
mix := PhHSlider new label: 'mix' values: #( 0.3 0 1 0.01 ).

"@(n): delay by n samples"
delay := [ :n | Wire new asBox , n asBox connectTo: 'process = @;' asBox ].

"lowpass(d) = *(1 - d) : + ~ *(d)"
lowpass := [ :d |
	Wire new asBox * (1 asBox - d asBox)
		connectTo: (Wire new asBox + Wire new asBox) ~ (Wire new asBox * d asBox) ].

"comb(n) = (+ : @(n)) ~ (lowpass(damp) : *(size))"
comb := [ :n |
	((Wire new asBox + Wire new asBox) connectTo: (delay value: n))
		~ ((lowpass value: damp) connectTo: Wire new asBox * size asBox) ].

"allpass(n, g) = (+ ~ (@(n - 1) : *(g))) <: @(n), *(-g) :> _"
allpass := [ :n :g | | loop |
	loop := (Wire new asBox + Wire new asBox)
		~ ((delay value: n - 1) connectTo: Wire new asBox * g asBox).
	(loop splitTo: (delay value: n) , (Wire new asBox * g negated asBox))
		mergeWith: Wire new asBox ].

"reverb = _ <: comb(1116), comb(1188), comb(1277), comb(1356) :> *(0.25) : allpass(556, 0.5) : allpass(225, 0.5)"
reverb := [ | combs allpasses |
	combs := (comb value: 1116) , (comb value: 1188) , (comb value: 1277) , (comb value: 1356).
	allpasses := (allpass value: 556 value: 0.5) connectTo: (allpass value: 225 value: 0.5).
	((Wire new asBox splitTo: combs) mergeWith: Wire new asBox * 0.25 asBox)
		connectTo: allpasses ].

"drywet(w, fx) = _ <: *(1 - w), (fx : *(w)) :> _"
drywet := [ :w :fx | | dry wet |
	dry := Wire new asBox * (1 asBox - w asBox).
	wet := fx connectTo: Wire new asBox * w asBox.
	(Wire new asBox splitTo: dry , wet) mergeWith: Wire new asBox ].

"Listen: a djembe hit every second"
source := Djembe new trigger: (Pulsen new period: 1).
dsp := (source asBox connectTo: (drywet value: mix value: reverb value)) stereo asDsp.
dsp init; start.
#( 'size' 'damp' 'mix' ) do: [ :each | dsp openSliderFor: each ].

"Stop"
dsp stop; destroy.

"Export: asDsp uses up its boxes, so the blocks build fresh ones"
(drywet value: mix value: reverb value) asDsp
	export2JuceWithName: 'PlainVerb' type: PhEffectPluginType new.
