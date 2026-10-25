# B3/BS4 verify with step-wise logging
LOG = "C:/Users/sr123/ijweb/headless/b3_verify.log"
log = open(LOG, "w")
try:
    log.write("step1-imports\n")
    from org.janelia.saalfeldlab.n5.zarr import N5ZarrReader
    from java.lang import Long
    log.write("step2-imports-ok\n")
    path = "E:/wx/zarr_out/14766.ome.zarr"
    r = N5ZarrReader(path)
    log.write("step3-reader-ok\n")
    for lvl in ["0", "1", "4"]:
        try:
            dims = r.getDatasetAttributes(lvl).getDimensions()
            log.write("level " + lvl + " dims=" + str([Long(d).intValue() for d in dims]) + "\n")
        except Throwable as e:
            log.write("level " + lvl + " ERR " + str(e)[:80] + "\n")
    r.close()
    log.write("step4-done\n")
except Throwable as e:
    log.write("FATAL " + e.getClass().getName() + ": " + str(e)[:200] + "\n")
log.close()
print("done")
