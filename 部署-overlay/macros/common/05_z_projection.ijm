// 05_z_projection.ijm — Z 投影（common；样例自举为 5 层栈）
if (nImages==0) {
  newImage("SampleStack", "8-bit ramp", 256, 256, 1, 1, 5);
}
if (nSlices > 1) {
  run("Z Projection...", "projection=[Max Intensity]");
  print("[05_z_projection] 完成：Max Intensity 投影，z=" + nSlices);
} else {
  print("[05_z_projection] 当前图为单层，跳过投影");
}
