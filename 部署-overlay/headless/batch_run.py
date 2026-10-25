# B2 batch runner (headless Jython) — PM-分支 BR3/BR4 合规
# 每输入文件恰好一行结果；单文件失败不中断；输出目录分离、_out 后缀、禁止原地覆盖
from ij import IJ
from java.io import File
import time

INPUT_DIR = "C:/Users/sr123/ijweb/B2_test_input"
OUTPUT_DIR = "C:/Users/sr123/ijweb/B2_test_output"
LOG = "C:/Users/sr123/ijweb/headless/batch_result.csv"
PROCESS = "Invert"  # 处理动作（ImageJ 命令名）；后续可换为宏路径执行

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
        secs = round(time.time() - t0, 1)
        ok += 1
        log.write("%s,OK,%s,%s\n" % (name, secs, outPath))
    except Exception as e:
        secs = round(time.time() - t0, 1)
        fail += 1
        msg = str(e).replace(",", ";").replace("\n", " ")[:100]
        log.write("%s,FAIL,%s,%s\n" % (name, secs, msg))
    log.flush()

log.write("SUMMARY,total=%d,ok=%d,fail=%d\n" % (total, ok, fail))
log.close()
print("BATCH_DONE total=%d ok=%d fail=%d" % (total, ok, fail))
