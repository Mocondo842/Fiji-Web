# verify the roundtrip OME-TIFF opens with correct dims (headless)
from ij import IJ

LOG = "C:/Users/sr123/ijweb/headless/r2t_verify.log"
log = open(LOG, "w")
imp = IJ.openImage("E:/wx/zarr_out/14766_view.ome.tif")
if imp is None:
    log.write("NULL\n")
else:
    log.write("OK %dx%d bit=%d ch=%d z=%d t=%d\n" % (imp.getWidth(), imp.getHeight(), imp.getBitDepth(), imp.getNChannels(), imp.getNSlices(), imp.getNFrames()))
    imp.close()
log.close()
print("done")
