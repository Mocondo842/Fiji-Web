# 桌面端格式对照矩阵（headless Jython；web 端结果见《复核记录-图像格式测试V13》）
from ij import IJ
from ij import WindowManager
from java.lang import Throwable

LOG = "C:/Users/sr123/ijweb/headless/matrix_result.log"
log = open(LOG, "w")

def out(line):
    print(line)
    log.write(line + "\n")
    log.flush()

base = "C:/Users/sr123/ijweb/imjoy-team-imagej.js-c25ef77/dist/testdata/"
files = ["tif_plain.tif", "tif_ome.ome.tif", "tif_rgb_3ch.tif",
         "nd2_sample.nd2", "czi_sample.czi", "mrc_sample.mrc", "ims_small.ims"]

out("DESKTOP_MATRIX_BEGIN ver=" + IJ.getFullVersion())
for f in files:
    path = base + f
    try:
        imp = IJ.openImage(path)
        how = "native"
        if imp is None:
            IJ.runPlugIn("loci.plugins.in.Importer", "open=[" + path + "]")
            imp = WindowManager.getCurrentImage()
            how = "bioformats"
        if imp is not None:
            out("RESULT %s OK-%s %dx%d bit=%d ch=%d z=%d t=%d" % (
                f, how, imp.getWidth(), imp.getHeight(), imp.getBitDepth(),
                imp.getNChannels(), imp.getNSlices(), imp.getNFrames()))
            imp.close()
        else:
            out("RESULT %s FAIL both-native-and-bioformats-none" % f)
    except Throwable as e:
        out("RESULT %s FAIL %s: %s" % (f, e.getClass().getSimpleName(), str(e)[:120]))
out("DESKTOP_MATRIX_END")
log.close()
