# batch_gui.py - robust GUI-triggered batch (reads dir from cfg; BS3-proven loop)
from ij import IJ
from java.io import File
import time

CFG = "C:/Users/sr123/ijweb/headless/batch_cfg.txt"
STATUS = "C:/Users/sr123/ijweb/headless/batch_status.txt"
LOG = "C:/Users/sr123/ijweb/headless/batch_result.csv"

lines = [l.strip() for l in open(CFG).read().splitlines() if l.strip()]
INPUT_DIR = lines[-1].replace("\\", "/")
OUTPUT_DIR = INPUT_DIR.rstrip("/") + "/out"
PROCESS = "Invert"

st = open(STATUS, "w")
st.write("RUNNING input=%s\n" % INPUT_DIR)
st.close()

log = open(LOG, "w")
log.write("file,status,seconds,output_or_error\n")
outDir = File(OUTPUT_DIR)
if not outDir.exists():
    outDir.mkdirs()
files = [f for f in File(INPUT_DIR).listFiles() if f.isFile()]
total = ok = fail = 0
for f in files:
    name = f.getName()
    total += 1
    t0 = time.time()
    try:
        imp = IJ.openImage(f.getAbsolutePath())
        if imp is None:
            raise Exception("openImage returned null (unsupported/corrupt)")
        IJ.run(imp, PROCESS, "")
        stem = name.rsplit(".", 1)[0]
        outPath = OUTPUT_DIR + "/" + stem + "_out.tif"
        IJ.saveAs(imp, "tif", outPath)
        imp.close()
        ok += 1
        log.write("%s,OK,%s,%s\n" % (name, round(time.time() - t0, 1), outPath))
    except Exception as e:
        fail += 1
        msg = str(e).replace(",", ";").replace("\n", " ")[:100]
        log.write("%s,FAIL,%s,%s\n" % (name, round(time.time() - t0, 1), msg))
    log.flush()
log.write("SUMMARY,total=%d,ok=%d,fail=%d\n" % (total, ok, fail))
log.close()

st = open(STATUS, "w")
st.write("DONE total=%d ok=%d fail=%d output=%s\n" % (total, ok, fail, OUTPUT_DIR))
st.close()
print("BATCH_DONE")
