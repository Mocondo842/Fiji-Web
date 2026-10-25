// debug 06: instrumented batch on ASCII dir (hardcoded) to locate the zero-output bug
LOG = "C:/Users/sr123/ijweb/headless/dbg_batch.log";
in = "C:/Users/sr123/ijweb/B2_test_input";
File.append("d0 in=" + in, LOG);
out = in + "/out" + File.separator;
File.append("d1 out=" + out, LOG);
File.makeDirectory(out);
list = getFileList(in);
File.append("d2 list.length=" + list.length, LOG);
n = 0;
for (i = 0; i < list.length; i++) {
  f = list[i];
  if (endsWith(f, ".tif") || endsWith(f, ".TIF") || endsWith(f, ".tiff")) {
    File.append("d3 match=" + f, LOG);
    open(in + File.separator + f);
    run("Invert");
    saveAs("tif", out + f);
    close();
    n = n + 1;
  }
}
File.append("d4 processed=" + n, LOG);
