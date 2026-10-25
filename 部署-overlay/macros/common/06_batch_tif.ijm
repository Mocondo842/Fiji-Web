// 06_batch_tif.ijm - GUI batch for TIFF family (branch B, button-driven)
// Pick an input folder, process every TIFF, save to <input>/out/ (BR4: never overwrite sources)
// NOTE: TIFF-family only in GUI mode; vendor formats (czi/nd2/ims/mrc) use the headless runner
in = getDirectory("Choose input folder");
if (in == "") exit();
out = in + "out" + File.separator;
File.makeDirectory(out);
list = getFileList(in);
n = 0;
for (i = 0; i < list.length; i++) {
  f = list[i];
  if (endsWith(f, ".tif") || endsWith(f, ".TIF") || endsWith(f, ".tiff")) {
    open(in + f);
    run("Invert");  // PROCESS step - edit per batch need
    saveAs("tif", out + f);
    close();
    n = n + 1;
  }
}
showMessage("Batch done", "Processed " + n + " TIFF file(s).\nOutput: " + out);
