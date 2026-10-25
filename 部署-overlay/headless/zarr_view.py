# zarr_view.py - open OME-Zarr in this GUI Fiji by calling N5Importer via CommandService (class name, no menu ambiguity)
#@ CommandService cs

CFG = "C:/Users/sr123/ijweb/headless/zarr_cfg.txt"
STATUS = "C:/Users/sr123/ijweb/headless/zarr_status.txt"

lines = [l.strip() for l in open(CFG).read().splitlines() if l.strip()]
path = lines[-1]

st = open(STATUS, "w")
try:
    st.write("RUNNING %s\n" % path)
    st.close()
    module = cs.run("org.janelia.saalfeldlab.n5.ij.N5Importer", False, {"n5": path}).get()
    st = open(STATUS, "a")
    st.write("IMPORTER_RETURNED\n")
except Throwable as e:
    st = open(STATUS, "a")
    st.write("EXC %s: %s\n" % (e.getClass().getName(), str(e)[:200]))
st.close()
