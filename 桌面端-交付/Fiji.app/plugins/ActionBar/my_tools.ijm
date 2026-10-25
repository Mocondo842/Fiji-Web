<line>
<button>
label=Stack->Images
arg=<macro>
if (nImages==0) newImage("SampleStack", "8-bit ramp", 256, 256, 1, 3, 1);
run("Stack to Images");
</macro>
</button>
<button>
label=Enhance Contrast
arg=<macro>
if (nImages==0) newImage("SampleContrast", "8-bit ramp", 256, 256, 1);
run("Enhance Contrast", "saturated=0.35");
</macro>
</button>
<button>
label=Invert
arg=<macro>
if (nImages==0) newImage("SampleInvert", "8-bit ramp", 256, 256, 1);
run("Invert");
</macro>
</button>
</line>
