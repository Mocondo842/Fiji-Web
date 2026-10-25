// 02_enhance_contrast.ijm — 增强对比度（common：saturated=0.35）
if (nImages==0) {
  newImage("SampleContrast", "8-bit ramp", 256, 256, 1);
}
run("Enhance Contrast", "saturated=0.35");
print("[02_enhance_contrast] 完成");
