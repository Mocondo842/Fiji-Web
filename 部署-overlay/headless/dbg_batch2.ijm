// debug 06b: fine-grained instrumentation per operation
LOG = "C:/Users/sr123/ijweb/headless/dbg_batch2.log";
in = "C:/Users/sr123/ijweb/B2_test_input";
out = in + "/out" + File.separator;
File.makeDirectory(out);
list = getFileList(in);
for (i = 0; i < list.length; i++) {
  f = list[i];
  if (endsWith(f, ".tif") || endsWith(f, ".TIF") || endsWith(f, ".tiff")) {
    File.append("A before-open " + f, LOG);
    open(in + File.separator + f);
    File.append("B after-open title=" + getTitle(), LOG);
    run("Invert");
    File.append("C after-invert", LOG);
    saveAs("tif", out + f);
    File.append("D after-save", LOG);
    close();
  }
}
File.append("E loop-end", LOG);
