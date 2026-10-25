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
arg=<bsh>
import ij.IJ;
import javax.swing.*;
JFileChooser fc = new JFileChooser();
fc.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
int ret = fc.showOpenDialog(null);
if (ret == JFileChooser.APPROVE_OPTION) {
  String sep = System.getProperty("file.separator");
  String in = fc.getSelectedFile().getAbsolutePath() + sep;
  String out = in + "out" + sep;
  new java.io.File(out).mkdirs();
  java.io.File[] fs = new java.io.File(in).listFiles();
  int ok = 0; int fail = 0;
  StringBuffer errs = new StringBuffer();
  for (int i = 0; i < fs.length; i++) {
    java.io.File f = fs[i];
    String n = f.getName().toLowerCase();
    if (n.endsWith(".tif") || n.endsWith(".tiff")) {
      try {
        ij.ImagePlus imp = IJ.openImage(f.getAbsolutePath());
        if (imp == null) throw new Exception("openImage null");
        IJ.run(imp, "Invert", "");
        IJ.saveAs(imp, "tif", out + f.getName());
        imp.close();
        ok++;
      } catch (Exception e) {
        fail++;
        errs.append(f.getName()).append(" : ").append(e.toString()).append("\n");
      }
    }
  }
  JOptionPane.showMessageDialog(null, "Batch done.  OK=" + ok + "  FAIL=" + fail + "\nOutput: " + out + (errs.length() > 0 ? "\n\nFailed:\n" + errs.toString() : ""));
}
</bsh>
</button>
<button>
label=Open Zarr
arg=<macro>
p = getString("OME-Zarr folder path:", "E:/wx/zarr_out/14766.ome.zarr");
if (p != "") run("HDF5/N5/Zarr/OME-NGFF ...", "n5=[" + p + "]");
</macro>
</button>
</line>
