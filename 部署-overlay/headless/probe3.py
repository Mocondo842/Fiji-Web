# triple probe: bsh plugin presence, N5 API zarr open, (macro exec tested separately)
from ij import IJ

LOG = "C:/Users/sr123/ijweb/headless/probe3.log"
log = open(LOG, "w")

# probe 1: legacy bsh plugin
try:
    r = IJ.runPlugIn("bsh", "return 1;")
    log.write("bsh_plugin=%s\n" % r)
except Throwable as e:
    log.write("bsh_plugin_EXC=%s\n" % e.getClass().getSimpleName())

# probe 2: N5 API direct open (virtual)
try:
    from org.janelia.saalfeldlab.n5.zarr import N5ZarrReader
    from org.janelia.saalfeldlab.n5.imglib2 import N5Utils
    rd = N5ZarrReader("E:/wx/zarr_out/14766.ome.zarr")
    dims = rd.getDatasetAttributes("0").getDimensions()
    log.write("n5_dims=%s\n" % [long(d) for d in dims])
    img = N5Utils.openVirtual(rd, "0")
    log.write("n5_virtual_ok numDim=%s\n" % img.numDimensions())
    rd.close()
except Throwable as e:
    log.write("n5_EXC=%s: %s\n" % (e.getClass().getSimpleName(), str(e)[:120]))

log.close()
print("done")
