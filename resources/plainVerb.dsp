declare name "PlainVerb";
declare description "A Schroeder reverb in plain Faust: no libraries, only primitives";

// Controls
size = hslider("size", 0.85, 0, 0.95, 0.01); // decay time
damp = hslider("damp", 0.4, 0, 0.9, 0.01);   // darkens the tail
mix  = hslider("mix", 0.3, 0, 1, 0.01);      // dry/wet

// One-pole lowpass: y = (1-d)*x + d*y'
lowpass(d) = *(1 - d) : + ~ *(d);

// Feedback comb: an echo every n samples, darker and quieter each time
comb(n) = (+ : @(n)) ~ (lowpass(damp) : *(size));

// Allpass: smears the echoes into a wash without colouring the sound
allpass(n, g) = (+ ~ (@(n - 1) : *(g))) <: @(n), *(-g) :> _;

// Four combs in parallel, then two allpasses in series
// (Freeverb's delay times, in samples)
reverb = _ <: comb(1116), comb(1188), comb(1277), comb(1356)
           :> *(0.25)
            : allpass(556, 0.5)
            : allpass(225, 0.5);

// Dry/wet mixer
drywet(w, fx) = _ <: *(1 - w), (fx : *(w)) :> _;

process = drywet(mix, reverb);
