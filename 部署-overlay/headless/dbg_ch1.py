# test openImage on the exact failing file
from ij import IJ

LOG = "C:/Users/sr123/ijweb/headless/dbg_ch1.log"
log = open(LOG, "w")
try:
    imp = IJ.openImage("C:/Users/sr123/ijweb/B2_test_input/h5_Multichannel_20261019_15230_raw_CH(CF405)_CH1.ome.tif")
    if imp is None:
        log.write("openImage NULL\n")
    else:
        log.write("OK %dx%d %d\n" % (imp.getWidth(), imp.getHeight(), imp.getBitDepth()))
        imp.close()
except Throwable as e:
    log.write("EXC " + e.getClass().getSimpleName() + ": " + str(e)[:150] + "\n")
log.close()
print("done")
