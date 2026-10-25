// 03_invert_image.ijm — 图像反相（common：最朴素的验证宏）
if (nImages==0) {
  newImage("SampleInvert", "8-bit ramp", 256, 256, 1);
}
run("Invert");
print("[03_invert_image] 完成");
