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
<button>
label=Split Channels
arg=<macro>
if (nImages==0) newImage("SampleRGB", "RGB black", 256, 256, 1, 3, 1);
run("Fire");
run("Split Channels");
</macro>
</button>
<button>
label=Z Projection
arg=<macro>
if (nImages==0) newImage("SampleStack", "8-bit ramp", 256, 256, 1, 1, 5);
run("Z Projection...", "projection=[Max Intensity]");
</macro>
</button>
<button>
label=Batch TIF
arg=<macro>
in = getDirectory("Choose input folder");
if (in != "") {
  File.append(in, "C:/Users/sr123/ijweb/headless/batch_cfg.txt");
  exec("C:\\Users\\sr123\\APP\\Fiji\\fiji.bat", "--headless", "--console", "--run", "C:/Users/sr123/ijweb/headless/batch_gui.py");
  showMessage("Batch started", "Batch is running in background (about half a minute).\nResults: C:/Users/sr123/ijweb/headless/batch_result.csv\nStatus: C:/Users/sr123/ijweb/headless/batch_status.txt\nOutput goes to <input>/out/");
}
</macro>
</button>
</line>
