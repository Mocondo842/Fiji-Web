# S5 像素抽样：tif_plain 三个坐标点（桌面端）
from ij import IJ

LOG = "C:/Users/sr123/ijweb/headless/pixels_result.log"
log = open(LOG, "w")
imp = IJ.openImage("C:/Users/sr123/ijweb/imjoy-team-imagej.js-c25ef77/dist/testdata/tif_plain.tif")
line = "DESKTOP_PIXELS %d,%d,%d" % (imp.getProcessor().getPixel(0, 0),
                                    imp.getProcessor().getPixel(1024, 1024),
                                    imp.getProcessor().getPixel(2047, 2047))
print(line)
log.write(line + "\n")
log.close()
